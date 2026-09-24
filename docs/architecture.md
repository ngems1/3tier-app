# Architecture

The same application runs on two platforms, each in its own VPC with its own
load balancer, database, KMS key, alarms and Terraform state:

- **Project 1, EC2** (`environments/dev`, `prod`): described first.
- **Project 2, ECS on Fargate** (`environments/ecs-dev`, `ecs-prod`): see
  [Project 2: ECS](#project-2-ecs-on-fargate).

The GitHub variable `DEPLOY_TARGET` (`ec2`, `ecs` or `both`) decides which
platform each push to `main` deploys to. Manual runs of *Deploy EC2* or
*Deploy ECS* always deploy to their own platform.

## Tiers

| Tier | Runs on | Details |
|---|---|---|
| Presentation | Web ASG (private web subnets) behind the public ALB | Nginx serves the versioned React build and proxies `/api/*` to the internal ALB. The ALB terminates TLS (ACM certificate, TLS 1.3 policy), redirects HTTP to HTTPS, and is protected by AWS WAF (common, known-bad-inputs and IP-reputation rule sets). |
| Application | App ASG (private app subnets) behind an internal ALB | FastAPI on uvicorn, run by systemd as an unprivileged user. It reads database credentials from the RDS-managed Secrets Manager secret and connects to MySQL over verified TLS. |
| Data | RDS MySQL 8.4 (isolated DB subnets) | Multi-AZ with KMS-encrypted storage. The parameter group forces TLS (`require_secure_transport`). Backups are automated, logs are exported to CloudWatch, and Enhanced Monitoring is on. |

Every tier spans three Availability Zones. Prod has a NAT gateway in each AZ;
dev shares one to save cost. Database subnets have no route to the internet.

## Request flow

`https://<env>.<domain>` → Route 53 alias → WAF → public ALB (443) → web
instance :80 → Nginx `/api/*` → internal ALB :80 → app instance :8000 →
RDS :3306 (TLS).

Until a domain is configured, there is no Route 53 record or certificate:
users reach the public ALB directly over HTTP on port 80 (temporary).

Nginx resolves the internal ALB's name through the VPC resolver on each
request (`resolver 169.254.169.253`). ALB IP addresses change over time, so a
name resolved only at startup would eventually go stale.

## Releases are immutable

Each commit on `main` produces one **release**, identified by its commit SHA:

- `s3://<artifact-bucket>/releases/<sha>/`: backend and frontend tarballs plus `SHA256SUMS`
- AMIs `cloudbatch818-three-tier-web-<sha>-*` and `cloudbatch818-three-tier-app-<sha>-*`, tagged `Version=<sha>`
- Container images `cloudbatch818-three-tier-frontend:<sha>` and `cloudbatch818-three-tier-backend:<sha>`
  in ECR (immutable tags, scanned on push; the release is blocked on CRITICAL
  findings). EC2 runs the AMIs; ECS runs the images. Both are built from the
  same commit.

Each AMI is a fully patched and hardened Amazon Linux 2023 image with the
release already installed: pinned Python dependencies in a virtualenv, or the
React build. Instances don't download code at boot. User data only writes
environment settings (database endpoint, secret ARN, internal ALB name).

Terraform picks the AMIs by `Version` tag. The version is also written into
the launch templates, so a new release creates new template versions and
starts a rolling ASG instance refresh:

- `min_healthy_percentage = 100` and `max_healthy_percentage = 200`: new
  instances launch and pass ALB health checks before old ones are terminated
- `auto_rollback = true`: if the new instances never become healthy, the ASG
  returns to the previous launch template version

The deployed version is recorded in SSM Parameter Store at
`/cloudbatch818-three-tier/<env>/deployed-version`, written by the pipeline
only after the rollout and smoke tests pass (so it always names a release
that worked). The parameter's history, together with
GitHub Environment deployments, forms the deployment log.

## Security controls

| Area | Control |
|---|---|
| Identity | GitHub OIDC with no stored AWS keys. Pipeline roles are separate: read-only plan, Packer build, and one deploy role per GitHub Environment. Runtime roles are separate per tier, and only the app role can read the DB secret. |
| Network access | Security groups are chained tier to tier. Only the public ALB accepts internet traffic (443, plus 80 for the redirect). There is no SSH: sshd is disabled in the images and access is through SSM Session Manager. |
| Secrets | RDS generates and rotates the master password in Secrets Manager (`manage_master_user_password`). No passwords exist in Git, tfvars or CI. The app re-reads the secret automatically after a rotation. |
| Encryption at rest | A customer-managed KMS key per environment (with rotation) covers RDS storage, Performance Insights, the DB secret, CloudWatch log groups (app, WAF, VPC flow logs) and the SNS topic. EBS root volumes and AMI snapshots are encrypted. S3 buckets are encrypted. |
| Encryption in transit | TLS 1.3 at the public ALB, and verified TLS from the app to RDS. |
| Instances | IMDSv2 only (hop limit 1), images patched at bake time, kernel network hardening, auditd, and a sandboxed systemd service (no new privileges, read-only filesystem). |
| Edge | AWS WAF managed rules, and ALB drops invalid headers. Access logs for both ALBs go to S3, and WAF logs go to CloudWatch. |
| Supply chain | Pinned dependencies, and pip-audit / npm audit / Trivy / Checkov / CodeQL gates before anything deploys. |

## Observability

- **Logs:** `/cloudbatch818-three-tier-<env>/web` (Nginx access and error) and
  `/cloudbatch818-three-tier-<env>/app` (API) are shipped by the CloudWatch Agent. VPC flow
  logs and WAF logs also go to CloudWatch, and ALB access logs go to S3.
  Retention is 30 days in dev and 365 in prod.
- **Metrics:** ALB, EC2, Auto Scaling and RDS metrics, plus memory and
  disk metrics from the agent (namespace `cloudbatch818-three-tier/<env>`, aggregated per ASG).
- **Alarms (notify SNS):**
  - For each tier: no healthy targets, unhealthy targets, 5XX errors, p95
    latency, CPU, memory, and in-service instances below the minimum
  - Public ALB 5XX errors
  - RDS: CPU, freeable memory, free storage, connections
- **Dashboard:** `cloudbatch818-three-tier-<env>` in CloudWatch, with alarm status,
  requests and errors, latency, CPU, memory, capacity and RDS panels.

## Project 2: ECS on Fargate

| Tier | Runs on | Details |
|---|---|---|
| Presentation | ECS service `frontend` (Fargate tasks in private frontend subnets) | Unprivileged Nginx container serving the React build on port 8080. |
| Application | ECS service `backend` (Fargate tasks in private backend subnets) | FastAPI container on port 8000, read-only root filesystem, non-root user. Reads the database credentials from the RDS-managed secret through its task role and connects over verified TLS (the RDS CA bundle is baked into the image). |
| Data | RDS MySQL 8.4 (isolated DB subnets) | Same `database` module and settings as EC2, in the ECS VPC. |

**Request flow:** `http(s)://<alb>` → WAF → public ALB → `/api/*` to the
backend target group (port 8000), everything else to the frontend target
group (port 8080). Target groups use IP targets, so the ALB talks to each
task directly. The ALB checks `/healthz` on both services.

**Releases.** Task definitions reference the images by digest
(`<repo>@sha256:…`), looked up from the release's SHA tag in ECR. A task
therefore always runs exactly the image that CI built and scanned. The
deployed SHA is recorded in `/cloudbatch818-three-tier-ecs/<env>/deployed-version`.

**Deployments.** A new release registers new task definitions and updates
both services:

- `minimum healthy 100%`, `maximum 200%`: new tasks start and pass ALB health
  checks before old ones stop
- Deployment circuit breaker with rollback: if new tasks keep failing, ECS
  returns the service to the previous task definition by itself
- The pipeline (`deploy/ecs/verify-deployment.sh`) waits until every service
  runs the new task definition, and fails the deploy if ECS rolled back

**Scaling.** Each service scales between its min and max task counts on 60%
average CPU (Application Auto Scaling target tracking). Terraform ignores the
running task count, so scaling isn't undone by the next deploy.

**Security controls** (in addition to the shared ones above):

| Area | Control |
|---|---|
| Identity | One task execution role (pull images, write logs) and one task role per service. Only the backend task role can read the database secret. |
| Network | Tasks have no public IPs. Security groups: ALB → frontend 8080 and backend 8000 only; backend → RDS 3306 only; tasks reach AWS APIs (ECR, logs, Secrets Manager) over HTTPS through the NAT gateway. |
| Containers | Non-root users in both images; read-only root filesystem for the backend; images scanned by Trivy in CI and by ECR on push. |

**Observability.** Container Insights on the cluster; logs in
`/cloudbatch818-three-tier-ecs-<env>/frontend` and `/backend` (KMS-encrypted);
alarms for running tasks below the minimum, CPU, memory, no healthy targets,
5XX errors and p95 latency per service, ALB 5XX, and RDS; dashboard
`cloudbatch818-three-tier-ecs-<env>`.
