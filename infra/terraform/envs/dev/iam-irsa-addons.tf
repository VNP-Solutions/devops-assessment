data "aws_iam_policy_document" "eso" {
statement {
effect = "Allow"
actions = [
"secretsmanager:GetSecretValue",
"secretsmanager:DescribeSecret",
"secretsmanager:ListSecrets"
]
resources = ["*"]
}
}
resource "aws_iam_policy" "eso" {
name = "${local.name_prefix}-external-secrets"
policy = data.aws_iam_policy_document.eso.json
tags = local.tags
}
data "aws_iam_policy_document" "fluentbit" {
statement {
effect = "Allow"
actions = [
"logs:CreateLogGroup",
"logs:CreateLogStream",
"logs:DescribeLogStreams",
"logs:PutLogEvents"
]
resources = ["*"]
}
}
resource "aws_iam_policy" "fluentbit" {
name = "${local.name_prefix}-fluentbit"
policy = data.aws_iam_policy_document.fluentbit.json
tags = local.tags
}
data "aws_iam_policy_document" "irsa_assume" {
for_each = {
eso = "system:serviceaccount:external-secrets:external-secrets"
fluentbit = "system:serviceaccount:kube-system:aws-for-fluent-bit"
}
statement {
    effect = "Allow"
actions = ["sts:AssumeRoleWithWebIdentity"]
principals {
type = "Federated"
identifiers = [module.eks.oidc_provider_arn]
}
condition {
test = "StringEquals"
variable = "${replace(module.eks.oidc_provider, "https://", "")}:aud"
values = ["sts.amazonaws.com"]
}
condition {
test = "StringEquals"
variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
values = [each.value]
}
}
}
resource "aws_iam_role" "irsa" {
for_each = data.aws_iam_policy_document.irsa_assume
name = "${local.name_prefix}-${each.key}-irsa"
assume_role_policy = each.value.json
tags = local.tags
}
resource "aws_iam_role_policy_attachment" "eso" {
role = aws_iam_role.irsa["eso"].name
policy_arn = aws_iam_policy.eso.arn
}
resource "aws_iam_role_policy_attachment" "fluentbit" {
role = aws_iam_role.irsa["fluentbit"].name
policy_arn = aws_iam_policy.fluentbit.arn
}