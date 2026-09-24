# Operational runbook

This runbook covers EC2 (Project 1) first; ECS (Project 2) has its own
section at the end: [ECS](#ecs-project-2).

Replace `<env>` with `dev` or `prod`. All commands assume AWS credentials
with the matching deploy (or admin) role and `AWS_REGION=us-east-1`.

## Where to look

| What | Where |
|---|---|
| Health at a glance | CloudWatch dashboard `cloudbatch818-three-tier-<env>` (alarm status in the top panel) |
| Web logs | Log group `/cloudbatch818-three-tier-<env>/web` (streams `<instance>/nginx-access`, `nginx-error`) |
| API logs | Log group `/cloudbatch818-three-tier-<env>/app` (stream `<instance>/backend`) |
| Edge and network | `aws-waf-logs-cloudbatch818-three-tier-<env>`, `/cloudbatch818-three-tier-<env>/vpc-flow-logs`, ALB access logs in `s3://cloudbatch818-three-tier-<env>-alb-logs-<account>/` |
| Database | RDS console (Enhanced Monitoring), exported `error` and `slowquery` logs |
| What's deployed | `aws ssm get-parameter --name /cloudbatch818-three-tier/<env>/deployed-version` (parameter history = deployment log), and the GitHub Environments page |

## Access (no SSH)

Instances have no SSH daemon and no key pairs. Use Session Manager:

```bash
aws ssm start-session --target <instance-id>
```

**Database access** goes through an app instance using SSM port forwarding:

```bash
aws ssm start-session --target <app-instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters host=<db-endpoint>,portNumber=3306,localPortNumber=13306
```

Then connect with `mysql -h 127.0.0.1 -P 13306 -u appadmin -p --ssl-mode=REQUIRED`.
The password is in the secret shown by
`terraform -chdir=infra/terraform/environments/<env> output db_secret_arn`.

## Smoke test after a deploy

CI runs this automatically. To run it by hand:

```bash
tests/smoke/smoke_test.sh <app_url> <expected-sha>   # app_url = terraform output app_url
```

It checks the HTTP→HTTPS redirect, web health, the React app, API readiness
(including the database), the task list, and the deployed version.

## Rollback

**Application rollback (the usual case).** Redeploy the last known-good release:

1. Find it. Use the *Previous release* line in the failed run's summary, the
   SSM parameter history, or the GitHub Environments page.
2. Go to **Actions → Deploy EC2 → Run workflow**, set `environment=<env>` and
   `version=<good-sha>`.
3. The pipeline skips the build, because the AMIs for that SHA still exist.
   It plans, applies (with approval for prod), and waits for the rolling
   refresh. Then it smoke-tests.

To do the same from a workstation: `deploy/ec2/deploy.sh <env> <good-sha>`.

**Automatic rollback.** If new instances never become healthy during a
refresh, the ASG rolls back to the previous launch template by itself. The
deploy job then fails with status `RollbackSuccessful`.

**Infrastructure rollback.** Revert the Terraform change in Git (a pull
request that reverts the commit) and merge. The pipeline plans and applies
the revert like any other change.

**Stop the bleeding fast.** If a bad release is serving errors and a
redeploy is too slow, cancel the running refresh with
`aws autoscaling cancel-instance-refresh --auto-scaling-group-name cloudbatch818-three-tier-<env>-<web|app>`,
then start a rollback:
`aws autoscaling rollback-instance-refresh --auto-scaling-group-name ...`.

## Incident procedure

1. **Acknowledge** the SNS alert, then open the dashboard to see which tier is alarming.
2. **Classify:**
   - `*-no-healthy-hosts` or `web-alb-elb-5xx`: outage. Check the target
     group health and instance status, and the API readiness endpoint.
   - `*-5xx`, `*-latency-p95`: degraded. Check API logs for errors, and
     RDS CPU and connections.
   - `*-cpu-high`, `*-memory-high`: capacity. Check whether the ASG is at
     max (see Scaling).
   - `rds-*`: database. Check storage (autoscaling is enabled up to the
     max), connections and slow query log.
3. **Mitigate.** Roll back if the alarm started with a deploy. Otherwise scale out,
   or fail over RDS (`aws rds reboot-db-instance --force-failover`) if the
   primary is impaired.
4. **Record** the timeline, impact, root cause and follow-ups in the incident log.

## Scaling

- Both ASGs use target tracking at 50% average CPU, within the min/max set in
  `infra/terraform/environments/<env>/main.tf`.
- **Permanent change:** edit the min, max and desired values in that file
  and merge.
- **Temporary change during an incident:**
  `aws autoscaling set-desired-capacity --auto-scaling-group-name cloudbatch818-three-tier-<env>-app --desired-capacity N`.
  Terraform ignores desired-capacity drift, so this won't be reverted by the
  next deploy.
- **Database:** storage autoscales up to `db_max_allocated_storage`. To
  change the instance class, edit `db_instance_class` and merge. In prod the
  change is applied in the maintenance window, and Multi-AZ keeps the
  database available.

## Patching

Images are rebuilt with the latest Amazon Linux security updates on every
release. To patch without code changes, run **Deploy EC2** manually with no
version: it builds a fresh release from `main` and rolls it out. Also rebuild
monthly, or after a critical CVE.

## Housekeeping

- Keep the AMIs of the last 10 or so releases per tier for rollback, and
  deregister older ones along with their snapshots.
- Destroy an environment you don't need (a test dev, the platform you stopped
  using): **Actions → Destroy → Run workflow**, pick the platform and
  environment, and type the stack name (`dev`, `prod`, `ecs-dev`, `ecs-prod`)
  to confirm. Prod needs approval and keeps a final database snapshot. If the
  run fails part-way, fix the error and run it again: it removes only what is
  left.

## ECS (Project 2)

Names use the prefix `cloudbatch818-three-tier-ecs-<env>`; the Terraform root is
`infra/terraform/environments/ecs-<env>`.

### Where to look

| What | Where |
|---|---|
| Health at a glance | CloudWatch dashboard `cloudbatch818-three-tier-ecs-<env>` |
| Services and tasks | ECS console → cluster `cloudbatch818-three-tier-ecs-<env>` → services `…-frontend`, `…-backend` (the **Deployments** and **Events** tabs show rollouts and failures) |
| Container logs | Log groups `/cloudbatch818-three-tier-ecs-<env>/frontend` and `/backend` |
| What's deployed | `aws ssm get-parameter --name /cloudbatch818-three-tier-ecs/<env>/deployed-version`; `terraform output images` shows the exact image digests |

### Rollback

1. Find the last good SHA (run summary, SSM parameter history, or the GitHub
   Environments page).
2. **Actions → Deploy ECS → Run workflow**, `environment=<env>`,
   `version=<good-sha>`. The images for that SHA are still in ECR (the last 50
   releases are kept), so nothing is rebuilt.

**Automatic rollback.** If new tasks keep failing to start or to pass health
checks, the deployment circuit breaker puts the service back on the previous
task definition. The deploy job then fails with "the deployment circuit
breaker rolled it back" and lists the service events.

### Common problems

- **Tasks stop right after starting:** check the stopped task's *Stopped
  reason* in the console and the container log group. `CannotPullContainerError`
  means the task can't reach ECR (NAT gateway, security group egress 443).
- **Backend unhealthy, `/api/healthz` returns 503:** the database is
  unreachable or the secret can't be read; check the backend logs for
  `1045` (credentials) or TLS errors.
- **Stuck deployment:** `aws ecs describe-services --cluster <cluster> --services <service>`
  shows the deployments and the latest events.

### Scaling

Each service scales on 60% average CPU between the `*_min_count` and
`*_max_count` values in `environments/ecs-<env>/main.tf`. For a temporary
change during an incident:

```bash
aws ecs update-service --cluster cloudbatch818-three-tier-ecs-<env> \
  --service cloudbatch818-three-tier-ecs-<env>-backend --desired-count N
```

Auto scaling may adjust it again within the min/max; raise the minimum in
Terraform for a lasting change.

### Access

Fargate tasks have no SSH, and ECS Exec is off. Use the logs and the API for
diagnosis. If you need a shell or database access, ECS Exec can be added to
the backend service (`enable_execute_command = true` plus the
`ssmmessages:*` permissions on the backend task role) through a reviewed
Terraform change, and removed afterwards.
