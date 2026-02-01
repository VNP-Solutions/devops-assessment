resource "aws_iam_openid_connect_provider" "github" {
url = "https://token.actions.githubusercontent.com"
client_id_list = ["sts.amazonaws.com"]
thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
data "aws_iam_policy_document" "gha_assume_role" {
statement {
actions = ["sts:AssumeRoleWithWebIdentity"]
effect = "Allow"
principals {
type = "Federated"
identifiers = [aws_iam_openid_connect_provider.github.arn]
}
condition {
test = "StringEquals"
variable = "token.actions.githubusercontent.com:aud"
values = ["sts.amazonaws.com"]
}
condition {
test = "StringLike"
variable = "token.actions.githubusercontent.com:sub"
values = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"]
}
}
}
resource "aws_iam_role" "github_actions" {
name = "${local.name_prefix}-github-actions"
assume_role_policy = data.aws_iam_policy_document.gha_assume_role.json
tags = local.tags
}
data "aws_iam_policy_document" "gha_permissions" {
statement {
effect = "Allow"
actions = [
"ecr:GetAuthorizationToken",
"ecr:BatchCheckLayerAvailability",
"ecr:CompleteLayerUpload",
"ecr:InitiateLayerUpload",
"ecr:UploadLayerPart",
"ecr:PutImage",
"ecr:BatchGetImage",
"ecr:DescribeRepositories"
]
resources = ["*"]
}
statement {
effect = "Allow"
actions = ["eks:DescribeCluster"]
resources = [module.eks.cluster_arn]
}
}
resource "aws_iam_policy" "gha" {
name = "${local.name_prefix}-gha-policy"
policy = data.aws_iam_policy_document.gha_permissions.json
tags = local.tags
}
resource "aws_iam_role_policy_attachment" "gha_attach" {
    role = aws_iam_role.github_actions.name
    policy_arn = aws_iam_policy.gha.arn
}