## What changes

<!-- One or two sentences: what this PR does and why. -->

## Where it deploys after merge

- [ ] EC2 (`deploy-ec2.yml`)
- [ ] ECS (`deploy-ecs.yml`)
- [ ] Nothing deployable (docs, CI only)

## Checks before merging

- [ ] CI is green (lint, tests, Terraform, Packer, security scans, CodeQL)
- [ ] I read the **Terraform plan** comments/summary for each deployed stack and nothing is replaced or destroyed unexpectedly (database, load balancers, VPC subnets)
- [ ] No secrets, keys or account-specific values added to the code
- [ ] Docs updated if behaviour or setup changed
