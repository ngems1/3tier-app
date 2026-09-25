# Manual bootstrap (AWS console, no Terraform)

This does by hand exactly what `infra/terraform/bootstrap` does. You only do it
once. You must be signed in as an administrator (root or a user/role with
`AdministratorAccess`).

Before you start, note two values and replace them everywhere below:

| Placeholder | Where to find it | Example |
|---|---|---|
| `ACCOUNT_ID` | Console, top right → your account name → the 12-digit **Account ID** | `123456789012` |
| `REPO` | Your GitHub repository as `owner/name` | `ngems1/3tier-app` |

`STATE_BUCKET` is the Terraform state bucket: `cloudbatch818-three-tier-tfstate-seb`.
Create it first (step 0).

Set the console region to **US East (N. Virginia) us-east-1** for the S3 steps.
IAM is global, so the region doesn't matter there.

---

## Step 0: state bucket

(Or run `infra/terraform/state-bucket` with Terraform instead.)

S3 → **Create bucket**
- Name: `cloudbatch818-three-tier-tfstate-seb`
- Region: us-east-1
- Block all public access: **on**
- Bucket versioning: **Enable**
- Default encryption: **SSE-KMS** with the AWS managed key `aws/s3`

The Terraform `backend` blocks already point at this name. If AWS says the
name is taken, pick another and update it in `state-bucket/variables.tf`,
`bootstrap/variables.tf`, `bootstrap/versions.tf` and
`environments/*/backend.tf`.

---

## Step 1: GitHub OIDC identity provider

IAM → **Identity providers** → **Add provider**
- Provider type: **OpenID Connect**
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

Skip this step if a provider with that URL already exists.

---

## Step 2: Artifact bucket

S3 → **Create bucket**
- Name: `cloudbatch818-three-tier-artifacts-ACCOUNT_ID`
- Region: us-east-1
- Block all public access: **on**
- Bucket versioning: **Enable**
- Default encryption: **SSE-KMS**, key `aws/s3`, Bucket Key **enabled**

Optional: Management → Lifecycle rule "cleanup", apply to all objects,
"Permanently delete noncurrent versions" after 30 days, and "Delete incomplete
multipart uploads" after 7 days.

---

## Step 2b: ECR repositories

ECR (region us-east-1) → **Create repository**, twice:
- Names: `cloudbatch818-three-tier-frontend` and `cloudbatch818-three-tier-backend`
- Visibility: Private
- Tag immutability: **Immutable**
- Scan on push: **on**
- Encryption: **KMS** (AWS managed key)

Optional: add a lifecycle policy that expires untagged images after 7 days
and keeps the latest 50 images.

---

## Step 3: Two permission policies

IAM → **Policies** → **Create policy** → **JSON** tab. Paste, click Next, set
the name, then **Create policy**.

### 3a. `cloudbatch818-three-tier-github-build`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PackerEc2",
      "Effect": "Allow",
      "Action": [
        "ec2:AttachVolume", "ec2:AuthorizeSecurityGroupIngress", "ec2:CopyImage", "ec2:CreateImage",
        "ec2:CreateKeyPair", "ec2:CreateSecurityGroup", "ec2:CreateSnapshot", "ec2:CreateTags",
        "ec2:CreateVolume", "ec2:DeleteKeyPair", "ec2:DeleteSecurityGroup", "ec2:DeleteSnapshot",
        "ec2:DeleteVolume", "ec2:DeregisterImage", "ec2:Describe*", "ec2:DetachVolume",
        "ec2:GetPasswordData", "ec2:ModifyImageAttribute", "ec2:ModifyInstanceAttribute",
        "ec2:ModifySnapshotAttribute", "ec2:RegisterImage", "ec2:RunInstances", "ec2:StopInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PublishArtifacts",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::cloudbatch818-three-tier-artifacts-ACCOUNT_ID",
        "arn:aws:s3:::cloudbatch818-three-tier-artifacts-ACCOUNT_ID/*"
      ]
    },
    {
      "Sid": "EcrLogin",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "PushAndScanImages",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
        "ecr:DescribeImages", "ecr:DescribeImageScanFindings", "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"
      ],
      "Resource": [
        "arn:aws:ecr:us-east-1:ACCOUNT_ID:repository/cloudbatch818-three-tier-frontend",
        "arn:aws:ecr:us-east-1:ACCOUNT_ID:repository/cloudbatch818-three-tier-backend"
      ]
    }
  ]
}
```

### 3b. `cloudbatch818-three-tier-github-deploy`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageStackServices",
      "Effect": "Allow",
      "Action": [
        "acm:*", "autoscaling:*", "cloudwatch:*", "ec2:*", "elasticloadbalancing:*",
        "kms:*", "logs:*", "rds:*", "route53:*", "secretsmanager:*", "sns:*", "ssm:*", "wafv2:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageProjectBuckets",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::cloudbatch818-three-tier-*",
        "arn:aws:s3:::cloudbatch818-three-tier-*/*"
      ]
    },
    {
      "Sid": "TerraformState",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::STATE_BUCKET",
        "arn:aws:s3:::STATE_BUCKET/*"
      ]
    },
    {
      "Sid": "ManageProjectIam",
      "Effect": "Allow",
      "Action": [
        "iam:*Role", "iam:*RolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole", "iam:UpdateAssumeRolePolicy", "iam:PassRole",
        "iam:*Policy", "iam:*PolicyVersion", "iam:ListPolicyVersions", "iam:*InstanceProfile"
      ],
      "Resource": [
        "arn:aws:iam::ACCOUNT_ID:role/cloudbatch818-three-tier-*",
        "arn:aws:iam::ACCOUNT_ID:policy/cloudbatch818-three-tier-*",
        "arn:aws:iam::ACCOUNT_ID:instance-profile/cloudbatch818-three-tier-*"
      ]
    },
    {
      "Sid": "ReadIam",
      "Effect": "Allow",
      "Action": ["iam:Get*", "iam:List*"],
      "Resource": "*"
    },
    {
      "Sid": "ServiceLinkedRoles",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "arn:aws:iam::ACCOUNT_ID:role/aws-service-role/*"
    }
  ]
}
```

---

## Step 4: Four roles

IAM → **Roles** → **Create role** → **Custom trust policy**. Paste the trust
policy, click Next, attach the permission policy listed, click Next, set the
role name, then **Create role**. Afterwards open each role, go to
**Edit** (Summary section), and set **Maximum session duration** to 2 hours for
the build and deploy roles.

All four trust policies have the same shape; only the `sub` values differ:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": SUB_VALUES
        }
      }
    }
  ]
}
```

| Role name | Replace `SUB_VALUES` with | Permission policy to attach |
|---|---|---|
| `cloudbatch818-three-tier-github-plan` | `["repo:REPO:pull_request", "repo:REPO:ref:refs/heads/main"]` | AWS managed **ReadOnlyAccess** |
| `cloudbatch818-three-tier-github-build` | `["repo:REPO:ref:refs/heads/main", "repo:REPO:environment:build"]` | `cloudbatch818-three-tier-github-build` |
| `cloudbatch818-three-tier-github-deploy-dev` | `["repo:REPO:environment:dev"]` | `cloudbatch818-three-tier-github-deploy` |
| `cloudbatch818-three-tier-github-deploy-prod` | `["repo:REPO:environment:prod"]` | `cloudbatch818-three-tier-github-deploy` |

Example for the dev deploy role with `REPO` = `ngems1/3tier-app`:

```json
"token.actions.githubusercontent.com:sub": ["repo:ngems1/3tier-app:environment:dev"]
```

---

## Step 5: Collect the values for GitHub

| GitHub setting | Value |
|---|---|
| Repository variable `AWS_REGION` | `us-east-1` |
| Repository variable `AWS_PLAN_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/cloudbatch818-three-tier-github-plan` |
| Repository variable `AWS_BUILD_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/cloudbatch818-three-tier-github-build` |
| Repository variable `ARTIFACT_BUCKET` | `cloudbatch818-three-tier-artifacts-ACCOUNT_ID` |
| Environment **dev** variable `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/cloudbatch818-three-tier-github-deploy-dev` |
| Environment **prod** variable `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/cloudbatch818-three-tier-github-deploy-prod` |

Then continue with "2. Configure GitHub" in `docs/setup.md`.

If you ever want Terraform to manage these later, run `terraform import` for
each resource in `infra/terraform/bootstrap`, or delete them and apply the
bootstrap instead.
