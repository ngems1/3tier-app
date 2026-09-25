# One-time setup

You need admin rights on the GitHub repository, and on AWS either an
administrator login (Option A) or someone who can create one IAM role for you
(Option B, below).

**Domain (optional for now):** without a domain, each environment is served
over plain HTTP at its load balancer's address (the `app_url` output, also
shown on the GitHub deployment). When you have a public Route 53 hosted zone
in the same account, uncomment `hosted_zone_name` and `record_name` in
`infra/terraform/environments/<env>/main.tf` and merge: the certificate,
HTTPS (with HTTP→HTTPS redirect) and `<env>.<domain>` are created
automatically. The project plan requires HTTPS, so treat HTTP-only as a
temporary state.

**Region:** everything runs in **us-east-1**, including the Terraform state.
Packer bakes the AMIs in the default VPC of us-east-1, so that default VPC
must exist (new accounts have one), or set the Packer `subnet_id` variable to
a public subnet.

Steps 1a and 1b create the state bucket and the CI roles. Pick one way to run
them:

- **Option A:** from AWS CloudShell (us-east-1) or a computer with Terraform
  and the AWS CLI configured with admin credentials (below).
- **Option B:** from GitHub Actions with the `Bootstrap AWS account`
  workflow; no Terraform or access keys on your computer (see
  [Option B](#option-b-run-1a-and-1b-from-github)).
- If you can't run Terraform at all, `docs/manual-bootstrap.md` does the same
  by hand in the console.

## 1a. State bucket (run once)

```bash
cd infra/terraform/state-bucket
terraform init
terraform apply
```

Creates `cloudbatch818-three-tier-tfstate-seb`, the encrypted, versioned
bucket that stores every other Terraform state. This folder keeps its own
small state locally; that's intentional. If the name is ever taken, change it
in `state-bucket/variables.tf`, `bootstrap/variables.tf` and every `backend`
block (`bootstrap/versions.tf`, `environments/*/backend.tf`).

## 1b. Bootstrap (run once)

```bash
cd ../bootstrap
terraform init
terraform apply
```

This creates the GitHub OIDC provider, the CI roles
(`cloudbatch818-three-tier-github-plan`, `-build`, `-deploy-dev`, `-deploy-prod`),
the release artifact bucket, and two ECR repositories
(`cloudbatch818-three-tier-frontend`, `cloudbatch818-three-tier-backend`: immutable
tags, scan on push, old images expire automatically). Its state goes into the
bucket from 1a.

Every AWS resource this repository creates is named `cloudbatch818-three-tier-…`
(variable `project` in the bootstrap, in `modules/app-stack` and in the Packer
template; keep them in sync, because the deploy roles may only manage IAM
resources and buckets with that prefix).

- If the account already has a GitHub OIDC provider, add `-var create_oidc_provider=false`.
- If your repository isn't `ngems1/3tier-app`, pass `-var github_repository=<owner>/<repo>`.

Keep the outputs: you need them in step 2.

## Option B: run 1a and 1b from GitHub

The workflow `.github/workflows/bootstrap.yml` runs both folders. It needs a
way into AWS before bootstrap has created any roles, so you (or your account
admin) create one role by hand, once.

**In the AWS console (us-east-1), as someone allowed to manage IAM:**

1. **IAM → Identity providers → Add provider**
   - Provider type: **OpenID Connect**
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
2. **IAM → Roles → Create role → Custom trust policy**, paste this and
   replace `<ACCOUNT_ID>` with your 12-digit account ID:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
             "token.actions.githubusercontent.com:sub": "repo:ngems1/3tier-app:environment:prod"
           }
         }
       }
     ]
   }
   ```

   - Permissions: skip for now (next step).
   - Role name: `cloudbatch818-three-tier-seb`
   - Copy the role ARN.

   Only jobs from this repository that run in the GitHub environment
   `prod` can use this role, and every one of them needs a reviewer's approval.
   The project uses just the two environments, `dev` and `prod`. (Trade-off:
   any job in `prod`, including prod deploys, could use this role; all of them
   wait for a reviewer first. For a stricter split, delete the role once
   bootstrap is done.)

3. Give the role only what bootstrap needs: open the role →
   **Add permissions → Create inline policy → JSON**, paste
   [`docs/bootstrap-role-policy.json`](bootstrap-role-policy.json), name it
   `cloudbatch818-three-tier-seb`. It allows:

   | Area | Allowed | Limited to |
   |---|---|---|
   | S3 | Create and manage buckets and state files | Buckets named `cloudbatch818-three-tier-*`; deleting the state bucket is denied |
   | IAM roles and policies | Create, update, delete, tag | Names starting with `cloudbatch818-three-tier-` |
   | Attaching policies to roles | Attach | Only AWS `ReadOnlyAccess` or the project's own policies |
   | OIDC provider | Read | The GitHub provider |
   | ECR | Create and manage repositories and lifecycle rules | Repositories `cloudbatch818-three-tier-*` in us-east-1 |
   | KMS | Grants for ECR encryption | Only when called through ECR |

   Deploying dev and prod doesn't use this role: bootstrap creates the
   `deploy-dev`/`deploy-prod` roles with their own permissions for that.
   Keep required reviewers on `prod` anyway: a role
   that can write IAM policies, even project-named ones, can grant broad
   rights through them.

**In GitHub:**

4. **Settings → Environments**: create the two environments now (their
   `AWS_DEPLOY_ROLE_ARN` values are added later, in "2. Configure GitHub",
   once bootstrap has created the deploy roles):
   - `dev`: no protection.
   - `prod`: **Required reviewers** (yourself), **Deployment branches**
     `main` only, and the environment variable `AWS_BOOTSTRAP_ROLE_ARN` = the
     role ARN from step 2.
5. Push the repository to `main`. GitHub only offers manual workflows that are
   on the default branch. The `Deploy EC2` run started by this push fails
   because the AWS variables aren't set yet; that's expected.

**Run it:**

6. **Actions → Bootstrap AWS account → Run workflow**, leave **apply**
   unchecked, approve the `prod` environment when asked. Check the plan in
   the run summary. (On the very first run only the state bucket plan is
   shown: bootstrap can't plan until the bucket exists.)
7. Run it again with **apply** checked. It creates the state bucket, moves the
   bucket's own Terraform state into it, then applies bootstrap.
8. The run summary ends with a table of every value for step 2.

Notes:

- The workflow always runs bootstrap with `create_oidc_provider=false`,
  because the provider from step 1 already exists. If you later run bootstrap
  from a computer, add `-var create_oidc_provider=false` there too.
- It's safe to re-run: it plans and applies only changes to these two folders.
  If the bucket exists without state (created from a computer or by hand), the
  workflow imports it instead of recreating it.
- Afterwards, either keep the bootstrap role for future changes to
  `infra/terraform/bootstrap` (it only runs after a `prod` reviewer
  approves), or delete the role and the `AWS_BOOTSTRAP_ROLE_ARN` variable. **Keep the OIDC
  provider:** every pipeline role uses it.

## VPC quota full: use an existing VPC

Each environment normally creates its own VPC. If `terraform apply` fails with
`VpcLimitExceeded`, the region has no room for another VPC. Either ask the
account admin to raise **Service Quotas → Amazon VPC → VPCs per Region** or
remove unused VPCs, or build the stack inside a VPC that already exists:

In `infra/terraform/environments/<env>/main.tf` set

```hcl
existing_vpc_id = "vpc-0123456789abcdef0"   # must have an internet gateway
vpc_cidr        = "172.31.0.0/16"           # that VPC's CIDR, for reference
```

and choose subnet ranges inside that VPC that no other subnet uses (check
**VPC → Subnets**, filtered by the VPC). The stack still gets its own public,
private and database subnets, NAT gateway, route tables, flow logs (per
subnet) and security groups. It never changes the VPC itself, its internet
gateway, its default security group or other subnets, and Destroy removes only
what the stack created.

This repository is currently set up this way: all four stacks use the default
VPC `vpc-0e13ae6de03f62cd5` (172.31.0.0/16) with separate /24 blocks (dev
172.31.128–139, prod 172.31.144–155, ecs-dev 172.31.160–171, ecs-prod
172.31.176–187). Trade-off: other workloads in the same VPC are on the same
network, so the security groups (not the VPC boundary) are what keeps them out.
To go back to a dedicated VPC, delete `existing_vpc_id` and set a new
`vpc_cidr` and subnet ranges (e.g. `10.75.0.0/16`).

## 2. Configure GitHub

**Repository variables** (Settings → Secrets and variables → Actions → Variables):

| Variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `AWS_PLAN_ROLE_ARN` | bootstrap output `plan_role_arn` |
| `AWS_BUILD_ROLE_ARN` | bootstrap output `build_role_arn` |
| `ARTIFACT_BUCKET` | bootstrap output `artifact_bucket` |
| `DEPLOY_TARGET` | Where pushes to `main` deploy: `ec2` (default if unset), `ecs` or `both` |

**Environments** (Settings → Environments):

| Environment | Variable | Protection |
|---|---|---|
| `dev` | `AWS_DEPLOY_ROLE_ARN` = `deploy_role_arns["dev"]` | none (deploys automatically) |
| `prod` | `AWS_DEPLOY_ROLE_ARN` = `deploy_role_arns["prod"]` | **Required reviewers** (at least one person); deployment branches limited to `main` |

No AWS secrets are stored in GitHub. The roles trust only this repository,
and each deploy role trusts only its own environment. EC2 and ECS use the
same two environments, so one prod approval rule and one deploy role per
environment cover both platforms.

**Branch protection for `main`** (Settings → Rules → Rulesets):

- Require a pull request before merging, with at least 1 approval
- Require these status checks to pass: `Backend (FastAPI)`, `Frontend (React)`,
  `Terraform`, `Packer`, `Security scans`, `CodeQL (python)`,
  `CodeQL (javascript-typescript)`
- Block force pushes and deletions

CodeQL needs code scanning enabled. That's free for public repositories and
requires GitHub Advanced Security for private ones.

## 3. Alarm notifications (optional)

To receive alarm emails, set `alarm_emails` in
`infra/terraform/environments/<env>/main.tf` (EC2) or
`infra/terraform/environments/ecs-<env>/main.tf` (ECS), e.g.
`alarm_emails = ["you@example.com"]`. Then confirm the subscription email
that AWS sends.

## 4. First deployment

Pick the platform with `DEPLOY_TARGET` and merge to `main`, or run a deploy
workflow by hand:

- **EC2:** the first deploy bakes the AMIs (about 10 minutes), then creates
  the dev stack (about 20–30 minutes, mostly RDS Multi-AZ).
- **ECS:** the first deploy builds and scans the two images, creates the
  `ecs-dev` stack (about 20–30 minutes, mostly RDS Multi-AZ), and waits for
  the services to start.

A push to `main` deploys dev and then waits for approval to deploy prod. A
manual run (**Actions → Deploy EC2** or **Deploy ECS → Run workflow**)
deploys only the environment you pick.

The URL of each environment is in the run summary and on the GitHub
Environments page. Both platforms report to the same `dev` and `prod`
environments, so the page shows the URL of whichever was deployed last.

## 5. Removing an environment

Run **Actions → Destroy → Run workflow** and choose the platform and the
environment. To confirm, type the stack name: `dev`, `prod`, `ecs-dev` or
`ecs-prod`.

- It runs in the matching GitHub Environment, so destroying prod needs a
  reviewer's approval, like deploying it.
- It waits if a deployment of the same platform is running.
- It turns off deletion protection on the load balancers and database first,
  then removes everything in that stack. Prod keeps a final database snapshot
  (`<project>-prod-final`); dev doesn't.
- It keeps what you need to come back: the state bucket, CI roles, ECR images
  and AMIs. Run the deploy workflow to recreate the environment.

**Switching platforms doesn't remove the other one.** Destroy the stacks of
the platform you no longer use, so you stop paying for them.

## Migrating from the previous layout

The old stack (Terraform workspaces, root-level `main.tf`) and this one use
different state files and resource names, so they don't conflict, but they
cost money side by side. Once the new dev environment works:

1. Export any data you need from the old RDS instance, e.g. through SSM port
   forwarding (see the runbook).
2. Destroy the old stack from the old repository: `terraform workspace select dev && ./dev-destroy.sh`.
3. Delete the old AMIs named `three-tier-frontend` and `three-tier-backend` if
   you no longer need them.
