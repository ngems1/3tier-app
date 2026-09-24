# Release checklist

Most items are enforced by the pipeline. The reviewer confirms the rest
before approving a production deployment.

## Before merging (pull request)

- [ ] CI is green: backend lint, tests and audit; frontend lint, tests, build and audit
- [ ] Terraform fmt, validate and offline tests pass; the Packer template validates
- [ ] Checkov, Trivy and CodeQL show no new high or critical findings
- [ ] The Terraform plans for every deployed environment (EC2 and/or ECS, in the PR checks) show only the intended changes
- [ ] The change is reviewed and approved by at least one other person

## Before approving prod

- [ ] The dev deployment of this exact release succeeded (EC2 instance refresh or ECS rollout, plus smoke tests)
- [ ] The prod plan in the run summary shows only the intended changes, with no unexpected replacement or destroy
- [ ] Database changes are backward compatible with the previous release, so a rollback is possible
- [ ] The previous release SHA is noted (it's in the run summary) in case a rollback is needed
- [ ] No active incident or alarm in prod

## After the prod deployment

- [ ] EC2: the instance refresh completed (not `RollbackSuccessful`). ECS: both services run the new task definition (not rolled back by the circuit breaker)
- [ ] Smoke tests passed
- [ ] The dashboard (`cloudbatch818-three-tier-prod` or `cloudbatch818-three-tier-ecs-prod`) shows no alarms; error rate and latency are normal for 15 minutes
- [ ] New logs (`/cloudbatch818-three-tier-prod/web` and `/app`, or `/cloudbatch818-three-tier-ecs-prod/frontend` and `/backend`) show no unexpected errors
