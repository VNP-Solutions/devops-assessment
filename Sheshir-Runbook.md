# Sheshir-Runbook

## What I’m deploying

I deploy the **toy-production** stack into an **EKS** cluster in **us-east-1**:

- AWS Load Balancer Controller (so my Ingress can create an ALB)
- External Secrets Operator (ESO) (so Kubernetes Secrets are synced from AWS Secrets Manager)
- The toy-production Helm chart (user-service, product-service, order-service, redis URL config, DB init job)
- A GitHub Actions workflow that builds/pushes images to ECR and deploys to EKS using OIDC (no long-lived AWS keys)

---
## Provision the Infra 
To provision the infrastructure using IaC (specifically Terraform), I have created a remote state on my local workstation.(Preferably A Linux machine)
```
export AWS_REGION=us-east-1
export TF_STATE_BUCKET="toy-prod-tfstate-<your-unique-suffix>"
export TF_STATE_TABLE="toy-prod-tflock"
aws s3api create-bucket \
 --bucket "${TF_STATE_BUCKET}" \
 --region "${AWS_REGION}" \
 --create-bucket-configuration LocationConstraint="${AWS_REGION}"
aws s3api put-bucket-versioning \
 --bucket "${TF_STATE_BUCKET}" \
 --versioning-configuration Status=Enabled
aws dynamodb create-table \
 --table-name "${TF_STATE_TABLE}" \
 --attribute-definitions AttributeName=LockID,AttributeType=S \
 --key-schema AttributeName=LockID,KeyType=HASH \
 --billing-mode PAY_PER_REQU
 ```

Apply the commands below in `/infra/terraform/envs/dev` for creating the infrastructure in one go!
```
cd infra/terraform/envs/dev
terraform init \
 -backend-config="bucket=${TF_STATE_BUCKET}" \
 -backend-config="key=toy-production/dev/terraform.tfstate" \
 -backend-config="region=${AWS_REGION}" \
 -backend-config="dynamodb_table=${TF_STATE_TABLE}"
terraform apply \
 -var="aws_region=${AWS_REGION}" \
 -var="project=toy-production" \
 -var="env=dev" \
 -var="github_org=<YOUR_GH_ORG>" \
 -var="github_repo=<YOUR_GH_REPO>"
 ```
For reference and in case of troubleshoot, this is the actual directory tree for the terraform 
```
infra/
 terraform/
 envs/dev/
deploy/
 helm/toy-production/
scripts/
 eks/
 observability/
.github/workflows/
Sheshir-Runbook.md
```
## One-go procedure (end-to-end)

### 1) Prereqs I check once

I make sure I have:

- An EKS cluster running and kubectl access from my machine
- An RDS Postgres instance reachable from EKS nodes (security group / routing)
- ECR repositories created for:
  - `toy-production-dev-user-service`
  - `toy-production-dev-product-service`
  - `toy-production-dev-order-service`
- A Secrets Manager secret that contains the DB connection string property `database_url`
- A Redis endpoint

I also confirm my local tools are installed:

```bash
aws --version
kubectl version --client
helm version
eksctl version
```

---

### 2) Install / fix AWS Load Balancer Controller (ALB Ingress)

If any old/broken ALB webhooks exist, they block API calls and Helm installs. I remove them first (safe if controller is absent/broken):

```bash
kubectl get mutatingwebhookconfiguration -o name | grep -E "elbv2\.k8s\.aws|aws-load-balancer" || true
kubectl get validatingwebhookconfiguration -o name | grep -E "elbv2\.k8s\.aws|aws-load-balancer" || true

kubectl get mutatingwebhookconfiguration -o name | grep -E "elbv2\.k8s\.aws|aws-load-balancer" | xargs -r kubectl delete
kubectl get validatingwebhookconfiguration -o name | grep -E "elbv2\.k8s\.aws|aws-load-balancer" | xargs -r kubectl delete

kubectl delete svc -n kube-system aws-load-balancer-webhook-service --ignore-not-found
```

Then I (re)install the controller using IRSA.

#### 2.1 Create/Reuse IAM policy for the controller

If the policy already exists, I reuse it:

```bash
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json

aws iam create-policy   --policy-name AWSLoadBalancerControllerIAMPolicy   --policy-document file://iam_policy.json || true

POLICY_ARN=$(aws iam list-policies --scope Local   --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn | [0]"   --output text)

echo "$POLICY_ARN"
```

#### 2.2 Create the IRSA service account

```bash
eksctl create iamserviceaccount   --cluster=toy-production-dev-eks   --namespace=kube-system   --name=aws-load-balancer-controller   --attach-policy-arn="$POLICY_ARN"   --override-existing-serviceaccounts   --region us-east-1   --approve
```

#### 2.3 Install the Helm chart and CRDs

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller   -n kube-system   --set clusterName=toy-production-dev-eks   --set serviceAccount.create=false   --set serviceAccount.name=aws-load-balancer-controller   --set replicaCount=2   --set enableServiceMutatorWebhook=false   --version 1.14.0

wget https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml
kubectl apply -f crds.yaml
```

#### 2.4 Verify it is actually running

```bash
kubectl get deploy -n kube-system aws-load-balancer-controller
kubectl get pods  -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o wide
kubectl get endpoints -n kube-system aws-load-balancer-webhook-service -o wide
kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=200
```

If pods don’t exist and I see “serviceaccount not found”, I create the service account (the IRSA step above) or fix the namespace mismatch.

---

### 3) Install External Secrets Operator (ESO)

I install ESO with CRDs and my IRSA annotation:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets   --namespace external-secrets   --create-namespace   --version 0.9.11   --set installCRDs=true   --set serviceAccount.create=true   --set serviceAccount.name=external-secrets   --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::222066942466:role/toy-production-dev-eso-irsa"
```

> Note: I use a chart/version compatible with my cluster. When I saw a CRD schema error like `selectableFields: field not declared in schema`, it meant a version mismatch between the CRD definitions and my API server expectations. Pinning the chart version + letting Helm install CRDs fixed it for me.

---

### 4) Configure ESO access to AWS Secrets Manager (ClusterSecretStore)

I apply a `ClusterSecretStore` named `aws-secretsmanager` that points to my region and uses the ESO service account.

Example (I keep this in Git):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

Apply it:

```bash
kubectl apply -f deploy/k8s/clustersecretstore.yaml
kubectl get clustersecretstore aws-secretsmanager -o yaml | head -40
```

---

### 5) Build and push images to ECR

I tag images with a real immutable tag (I use the Git SHA in CI). I verify tags exist in ECR:

```bash
aws ecr list-images --region us-east-1 --repository-name toy-production-dev-order-service
aws ecr list-images --region us-east-1 --repository-name toy-production-dev-user-service
aws ecr list-images --region us-east-1 --repository-name toy-production-dev-product-service
```

If I only see digests and no `latest`, I do **not** deploy `:latest`. I deploy the tag that exists (for example `manual-20260128132358` or a Git SHA).

---

### 6) Prepare Helm values for the app

My `values-dev.yaml` needs to match **real ECR repos** and a **real image tag**:

```yaml
namespace: toy-production

global:
  imageTag: "<GIT_SHA_OR_TAG>"
  awsRegion: "us-east-1"
  healthDeepCheck: "true"

images:
  userServiceRepo: "222066942466.dkr.ecr.us-east-1.amazonaws.com/toy-production-dev-user-service"
  productServiceRepo: "222066942466.dkr.ecr.us-east-1.amazonaws.com/toy-production-dev-product-service"
  orderServiceRepo: "222066942466.dkr.ecr.us-east-1.amazonaws.com/toy-production-dev-order-service"

redis:
  url: "redis://<redis-endpoint>:6379"

databaseSecret:
  awsSecretName: "<db-secret-name-in-secrets-manager>"
  property: "database_url"
```

---

### 7) Deploy the application (namespace + Helm)

I let Helm create the namespace and I avoid rendering a `Namespace` object inside the chart (to prevent Helm “ownership” conflicts).

```bash
helm upgrade --install toy-production deploy/helm/toy-production   -n toy-production   --create-namespace   -f deploy/helm/toy-production/values-dev.yaml   --set global.imageTag="<GIT_SHA_OR_TAG>"   --wait --timeout 20m
```

I verify:

```bash
kubectl get pods -n toy-production
kubectl get svc  -n toy-production
kubectl get ingress -n toy-production
kubectl get externalsecret -n toy-production
kubectl get secret -n toy-production toy-production-db -o jsonpath='{.data.DATABASE_URL}' | base64 -d; echo
```

---

### 8) Ensure DB init succeeds before services start

The chart includes a DB init Job. I watch it:

```bash
kubectl get job -n toy-production
kubectl logs -n toy-production job/toy-production-db-init --tail=200
```

If it hangs on “Waiting for DB…”, I check connectivity and SSL requirements (see troubleshooting).

---

### 9) Smoke test through the ALB

Once the Ingress is ready:

```bash
ALB_HOSTNAME=$(kubectl get ingress -n toy-production toy-production   -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "ALB = $ALB_HOSTNAME"
curl -i "http://${ALB_HOSTNAME}/health" || true
```

---

## GitHub Actions (build + push + deploy)

### 1) Workflow (example)

```yaml
name: build-and-deploy
on:
  push:
    branches: ["main"]
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      AWS_REGION: ${{ vars.AWS_REGION }}
      EKS_CLUSTER_NAME: ${{ vars.EKS_CLUSTER_NAME }}
      HELM_RELEASE: ${{ vars.HELM_RELEASE }}
      K8S_NAMESPACE: ${{ vars.K8S_NAMESPACE }}
      IMAGE_TAG: ${{ github.sha }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push images
        env:
          REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        run: |
          set -euo pipefail
          cd assessment
          USER_REPO="${REGISTRY}/toy-production-dev-user-service"
          PRODUCT_REPO="${REGISTRY}/toy-production-dev-product-service"
          ORDER_REPO="${REGISTRY}/toy-production-dev-order-service"

          docker build -f services/user-service/Dockerfile -t "${USER_REPO}:${IMAGE_TAG}" .
          docker build -f services/product-service/Dockerfile -t "${PRODUCT_REPO}:${IMAGE_TAG}" .
          docker build -f services/order-service/Dockerfile -t "${ORDER_REPO}:${IMAGE_TAG}" .

          docker push "${USER_REPO}:${IMAGE_TAG}"
          docker push "${PRODUCT_REPO}:${IMAGE_TAG}"
          docker push "${ORDER_REPO}:${IMAGE_TAG}"

      - name: Set kubeconfig
        run: |
          aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"
          kubectl get nodes

      - name: Deploy Helm chart
        run: |
          helm upgrade --install "${HELM_RELEASE}" deploy/helm/toy-production             -n "${K8S_NAMESPACE}"             --create-namespace             -f deploy/helm/toy-production/values-dev.yaml             --set global.imageTag="${IMAGE_TAG}"             --wait --timeout 20m

      - name: Smoke test (acceptance)
        run: |
          ALB_HOSTNAME=$(kubectl get ingress -n "${K8S_NAMESPACE}" toy-production             -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
          BASE_URL="http://${ALB_HOSTNAME}" ./assessment/scripts/acceptance.sh
```

### 2) OIDC role trust policy (must match repo exactly)

In IAM, the role `toy-production-dev-github-actions` must trust the GitHub OIDC provider and the `sub` condition must match the real repo format:

✅ Correct `sub` examples:

- `repo:<OWNER>/<REPO>:ref:refs/heads/main` (for pushes to main)
- `repo:<OWNER>/<REPO>:environment:<ENV_NAME>` (if using GitHub Environments)

Example trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::222066942466:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:MahmudulHasanSheshir/devops-assessment:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

---

## troubleshoot

### Broken AWS Load Balancer webhook blocked my installs

**What I saw:** Helm installs failed with a webhook error like “no endpoints available for service aws-load-balancer-webhook-service”.

**What I did:** I deleted stale webhook configurations and the broken webhook service, then reinstalled AWS Load Balancer Controller with IRSA and CRDs.

**Purpose:** Restore Kubernetes admission webhooks so normal resource creation works again.

```bash
kubectl get mutatingwebhookconfiguration -o name | grep -E "elbv2\.k8s\.aws|aws-load-balancer" | xargs -r kubectl delete
kubectl get validatingwebhookconfiguration -o name | grep -E "elbv2\.k8s\.aws|aws-load-balancer" | xargs -r kubectl delete
kubectl delete svc -n kube-system aws-load-balancer-webhook-service --ignore-not-found
```

---

### AWS Load Balancer Controller pods never created

**What I saw:** Deployment existed but no pods, and events said serviceaccount not found.

**What I did:** I created/attached the IRSA service account (`aws-load-balancer-controller`) and reinstalled the chart referencing `serviceAccount.create=false`.

**Purpose:** Ensure controller pods can be scheduled and can call AWS APIs.

---

### External Secrets CRD / schema mismatch

**What I saw:** Helm failed on ESO CRDs with schema errors (for example `selectableFields` or later `.data: field not declared in schema`).

**What I did:** I pinned a compatible ESO chart version (`0.9.11`) and used `installCRDs=true`. For app ExternalSecret objects, I ensured I used the correct fields for `external-secrets.io/v1beta1` (i.e., I used `spec.data` / `spec.dataFrom` and not an invalid top-level `.data`).

**Purpose:** Align manifests with the CRD schema actually installed in the cluster.

---

### DB init Job stuck in ContainerCreating due to missing ConfigMap / Secret

**What I saw:** The init job pod was pending with `configmap "toy-production-init-sql" not found` and later `secret "toy-production-db" not found`.

**What I did:** I fixed the chart/template so the ConfigMap renders correctly, and I installed ESO + ClusterSecretStore + ExternalSecret so `toy-production-db` is created.

**Purpose:** Make the DB init job mount its SQL and receive `DATABASE_URL`.

---

### Postgres connection failed due to special characters in password

**What I saw:** `psql` complained about “invalid percent-encoded token”, and the app readiness checks failed.

**What I did:** I URL-encoded the password and updated the Secrets Manager value so the connection string is valid.

**Purpose:** Ensure Postgres connection strings are syntactically correct.

```bash
export DBPW='MY_DB_PASSWORD'

python3 - <<'PY'
import os, urllib.parse
pw = os.environ["DBPW"]
print(urllib.parse.quote(pw, safe=""))
PY

unset DBPW
```

---

### Postgres rejected connections (pg_hba / SSL) and then TLS chain errors

**What I saw:** Readiness failed with:
- `no pg_hba.conf entry ... no encryption`
- later: `self-signed certificate in certificate chain`

**What I did:** I enforced SSL in the connection string using `?sslmode=require` and resynced the ExternalSecret so pods received the updated value.

**Purpose:** Meet the DB server’s encryption requirements and keep the app’s readiness check consistent with the DB TLS policy.

```bash
kubectl annotate externalsecret -n toy-production toy-production-db   force-sync="$(date +%s)" --overwrite

kubectl get secret -n toy-production toy-production-db -o jsonpath='{.data.DATABASE_URL}'   | base64 -d; echo
```

---

### Pods stuck in ImagePullBackOff because the tag didn’t exist

**What I saw:** `ImagePullBackOff` and events said `...:latest: not found`.

**What I did:** I listed ECR images and updated `global.imageTag` to a tag that actually exists (for example, a “manual-*” tag or the Git SHA I pushed in CI).

**Purpose:** Ensure Kubernetes pulls an existing image.

```bash
aws ecr list-images --region us-east-1 --repository-name toy-production-dev-order-service
```

---

### Helm “invalid ownership metadata” on Namespace / ClusterSecretStore

**What I saw:** Helm refused to install because resources already existed and had Helm annotations for a different release/namespace.

**What I did:** I deleted and recreated the namespace cleanly, and I ensured the chart does not render a `Namespace` manifest. For shared cluster-scoped resources like `ClusterSecretStore`, I either:
- managed them outside the app chart, or
- aligned ownership (only one Helm release should own it).

**Purpose:** Avoid Helm ownership conflicts that block installs/upgrades.



## Clean Up!
```
# Remove Kubernetes resources
helm uninstall toy-production -n toy-production
kubectl delete ns toy-production
# Destroy AWS resources
cd infra/terraform/envs/dev
terraform destroy \
 -var="aws_region=${AWS_REGION}" \
 -var="project=toy-production" \
 -var="env=dev" \
 -var="github_org=<YOUR_GH_ORG>" \
 -var="github_repo=<YOUR_GH_REPO>"
```
