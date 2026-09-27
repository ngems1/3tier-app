# Alignment with the project plan

Where each item of the *AWS 3-Tier Application Deployment Project Plan* is
implemented: Project 1 (EC2) first, then
[Project 2 (ECS)](#project-2-ecs-on-fargate). The GitHub variable
`DEPLOY_TARGET` chooses which platform pushes to `main` deploy to.

## Target architecture and enterprise baseline

| Plan item | Implementation |
|---|---|
| React + Nginx presentation tier | `app/frontend`; Nginx config in `deploy/ec2/web/` |
| FastAPI REST application tier | `app/backend/app` |
| MySQL data tier, preferably RDS | `infra/terraform/modules/database` (RDS MySQL 8.4) |
| ALB, TLS, private subnets | `modules/alb` (TLS 1.3 policy, HTTP→HTTPS redirect), `modules/dns` (ACM), `modules/network` |
| Auto scaling, health checks, least privilege | `modules/compute` (ASG, target tracking, ELB health checks, per-tier IAM) |
| Private DB, encryption, backups, controlled access | `modules/database`, `modules/security` (DB reachable only from the app SG) |
| Workloads across multiple AZs | 3 AZs for every subnet tier; NAT per AZ in prod; RDS Multi-AZ |
| IAM roles instead of long-lived keys | GitHub OIDC (`infra/terraform/bootstrap`), instance profiles |
| Encrypt data in transit and at rest | TLS at the ALB and to RDS (`require_secure_transport`); KMS key per environment (`modules/kms`) |
| Secrets in Secrets Manager or Parameter Store | RDS-managed secret (`manage_master_user_password`), read at runtime by `app/backend/app/db.py` |
| CloudWatch for logs and metrics | `modules/observability`, CloudWatch Agent config in `deploy/ec2/*/cloudwatch-agent.json` |
| Terraform for repeatable infrastructure | `infra/terraform` |

## Phase 1: Application foundation

| Plan item | Implementation |
|---|---|
| React frontend, FastAPI backend, MySQL data model | `app/frontend`, `app/backend`, `tasks` table (`app/backend/app/repository.py`) |
| CRUD APIs and `/healthz` | `GET/POST /api/tasks`, `GET/PUT/DELETE /api/tasks/{id}`, `/healthz` (liveness), `/api/healthz` (readiness) |
| Environment-based configuration | `app/backend/app/config.py` (`DB_*`, `DB_SECRET_ARN`, `APP_VERSION`) |
| Full stack locally with Docker Compose | `docker-compose.yml` |

## Phase 2: AWS foundation with Terraform

| Plan item | Implementation |
|---|---|
| VPC, public/private subnets, route tables, NAT/IGW | `modules/network` |
| ALB, security groups, IAM roles, launch template, ASG | `modules/alb`, `modules/security`, `modules/compute` |
| RDS MySQL in private subnets | `modules/database` (isolated subnets with no internet route) |
| Encrypted remote state; separate dev/prod variables | S3 backend with `encrypt` and locking; `environments/dev` and `environments/prod` each have their own state key |

## Phase 3: EC2 application packaging

| Plan item | Implementation |
|---|---|
| Hardened EC2 images or user-data bootstrap | Versioned Packer AMIs (`deploy/ec2/packer`), hardening in `deploy/ec2/common/harden.sh` |
| Nginx and runtime via automated provisioning | `deploy/ec2/web/provision-web.sh`, `deploy/ec2/app/provision-app.sh` |
| Frontend and backend as managed services | `nginx.service`; `three-tier-backend.service` (systemd, sandboxed) |
| CloudWatch Agent, logging, health checks | `configure-cloudwatch.sh`, log groups, ALB target group health checks on `/healthz` |

## Phase 4: GitHub Actions CI/CD

| Plan item | Implementation |
|---|---|
| PR: lint/test, build validation, fmt/validate, Checkov, Trivy, code quality | `.github/workflows/ci.yml` (ruff, pytest, eslint, jest, build, Terraform fmt/validate/test, Packer validate, Checkov, Trivy fs and image scans, CodeQL, pip-audit, npm audit) |
| Main: build release artifact, publish versioned package, deploy through an approved environment | `deploy-ec2.yml` → `release` job (S3 `releases/<sha>/` and AMIs tagged `Version=<sha>`) → plan/apply via GitHub Environments |
| GitHub OIDC deployment role | `bootstrap` roles plus `aws-actions/configure-aws-credentials` |
| Environment approvals for prod; deployment history | `prod` environment with required reviewers (`docs/setup.md`); GitHub deployments plus the SSM `deployed-version` parameter history |

## Phase 5: Security and reliability

| Plan item | Implementation |
|---|---|
| Least-privilege IAM; separate deployment and runtime roles | CI roles (plan, build, deploy per environment) in `bootstrap`; runtime roles per tier in `modules/compute/iam.tf` |
| SGs restricted by tier; only ALB ports public | `modules/security`; no SSH anywhere (SSM Session Manager) |
| Encrypt EBS, RDS, logs, supported storage | Encrypted launch template volumes and AMI snapshots, KMS for RDS, logs, secret and SNS; encrypted S3 buckets |
| Backups, ALB/EC2 health checks, Auto Scaling, controlled rollback | RDS backups (7 days dev, 30 prod) and final snapshot in prod; ELB health checks; rolling refresh with `auto_rollback`; redeploy-by-SHA rollback |

## Phase 6: Observability and release

| Plan item | Implementation |
|---|---|
| Dashboards and alarms: ALB, EC2, ASG, RDS, CPU, memory, latency, errors | `modules/observability` (dashboard plus alarms for each) |
| Centralized logs with retention | Log groups per tier (30 days dev, 365 prod), WAF, flow logs, ALB access logs |
| Smoke tests and rollback validation | `tests/smoke/smoke_test.sh` runs after every deploy; rollback procedure in `docs/runbook.md` |
| Runbook and release checklist | `docs/runbook.md`, `docs/release-checklist.md` |

## EC2 acceptance criteria

| Criterion | How it's met |
|---|---|
| Reachable through the ALB using HTTPS | ACM certificate plus HTTPS listener; the smoke test checks HTTPS and the redirect |
| Frontend calls the API and persists task data in RDS | Tasks UI → `/api/tasks` → RDS; the smoke test checks readiness (database up) and the task list |
| EC2 created by Terraform and able to scale through the ASG | `modules/compute` with target-tracking policies |
| Every PR validated; approved changes deployed from main | `ci.yml` required checks; `deploy-ec2.yml` on push to main with the prod approval gate |
| No long-lived AWS keys in GitHub | OIDC roles only; no AWS secrets configured |
| CloudWatch logs, metrics and alarms available | `modules/observability` |
| Failed deployment can be rolled back with the documented procedure | Automatic refresh rollback, plus redeploy-by-SHA (`docs/runbook.md`) |

## Standard pipeline stages (plan section 4)

| Stage | Where |
|---|---|
| 1. Pull request | `ci.yml` |
| 2. Build (artifacts tagged with commit SHA, no mutable tags) | `deploy-ec2.yml` `release` job |
| 3. Security | `ci.yml` `security`, `codeql`, audits |
| 4. Publish | S3 `releases/<sha>/`, SHA-tagged AMIs, and SHA-tagged images in ECR (immutable tags, scan-on-push gate) |
| 5. Deploy dev (OIDC → Terraform → smoke tests) | `plan-dev` / `apply-dev` |
| 6. Promote (environment approval, protected branch) | `prod` environment reviewers; branch ruleset (`docs/setup.md`) |
| 7. Production deploy (controlled rollout, monitor health) | `apply-prod`: rolling refresh, wait, smoke tests |
| 8. Rollback (redeploy last known-good immutable version) | `workflow_dispatch` with `version=<sha>` |

## Project 2: ECS on Fargate

The same application, enterprise baseline and pipeline stages as Project 1,
with containers instead of instances. Shared modules (`network`, `database`,
`dns`, `kms`) keep the two projects' controls identical.

| Capability | Implementation |
|---|---|
| Container images for frontend and backend | `app/frontend/Dockerfile` (unprivileged Nginx), `app/backend/Dockerfile` (non-root, RDS CA bundle included) |
| Private registry, immutable versioned images | ECR repositories from `bootstrap` (immutable tags, scan on push, lifecycle); images tagged with the commit SHA by `reusable-images.yml` |
| Image vulnerability gate | Trivy image scans in CI; ECR scan gate blocks CRITICAL findings before deploy |
| ECS cluster, task definitions, services | `modules/ecs` (Fargate, Container Insights, task definitions pinned by image digest) |
| Load balancing and routing | `modules/ecs-alb`: public ALB, `/api/*` → backend, rest → frontend, IP target groups, WAF, access logs, HTTPS when a domain is set |
| Private networking, least-privilege traffic | Separate VPC (`modules/network`), tasks in private subnets without public IPs, `modules/ecs-security` security groups tier to tier |
| Separate runtime roles | Task execution role plus one task role per service; only the backend can read the DB secret (`modules/ecs`) |
| Secrets | RDS-managed secret read at runtime by the backend (`DB_SECRET_ARN`); no credentials in task definitions (checked by the tests) |
| Auto scaling | Application Auto Scaling target tracking on CPU per service |
| Health checks and safe rollouts | ALB health checks, container health checks, rolling deploys at 100%/200%, deployment circuit breaker with automatic rollback |
| Separate dev and prod | `environments/ecs-dev`, `environments/ecs-prod`, each with its own state file |
| CI/CD with OIDC and approvals | `deploy-ecs.yml`: CI → images → plan/apply `ecs-dev` → smoke tests → prod approval → plan/apply `ecs-prod` → smoke tests; same OIDC roles and GitHub Environments as EC2 |
| Rollback | Automatic (circuit breaker, detected by `deploy/ecs/verify-deployment.sh`), or redeploy a previous SHA with *Deploy ECS* (`docs/runbook.md`) |
| Observability | `modules/ecs-observability`: alarms (running tasks, CPU, memory, healthy targets, 5XX, p95 latency, RDS) and a dashboard; container logs in CloudWatch |
| Offline tests | `modules/ecs-stack/tests` (digest pinning, rollback settings, no public IPs, secret handling, naming, HTTPS/HTTP modes) |

### ECS acceptance checks

| Check | How it's met |
|---|---|
| Frontend and API reachable through the ALB | Smoke tests after every deploy (`tests/smoke/smoke_test.sh`) |
| Tasks persist data in RDS | Smoke test checks API readiness (database up) and the task list |
| Services created by Terraform and able to scale | `modules/ecs` services with Application Auto Scaling |
| Approved changes deployed from `main` only | `deploy-ecs.yml` with the prod environment approval and branch ruleset |
| No long-lived AWS keys | OIDC roles only |
| Failed deployment rolls back | Circuit breaker rollback, plus redeploy-by-SHA |
