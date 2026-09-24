#!/usr/bin/env bash
# Deploy (or roll back to) a release from a workstation. CI normally does
# this; use it for break-glass operations with an admin/deploy role.
#
#   deploy/ec2/deploy.sh <dev|prod> <git-sha>
#
# Rollback = run it with the previous known-good SHA. Its AMIs still exist,
# so nothing is rebuilt: Terraform points the launch templates back at them
# and the ASGs do a rolling instance refresh.
set -euo pipefail

env="${1:?usage: deploy.sh <dev|prod> <git-sha>}"
version="${2:?usage: deploy.sh <dev|prod> <git-sha>}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tf_dir="${repo_root}/infra/terraform/environments/${env}"

[[ -d "${tf_dir}" ]] || { echo "Unknown environment: ${env}" >&2; exit 1; }
[[ "${version}" =~ ^[0-9a-f]{7,40}$ ]] || { echo "Version must be a git commit SHA" >&2; exit 1; }

cd "${tf_dir}"
terraform init -input=false
terraform plan -input=false -var "app_version=${version}" -out=tfplan

if [[ "${env}" == "prod" ]]; then
  read -r -p "Apply this plan to PRODUCTION? Type 'yes' to continue: " answer
  [[ "${answer}" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

terraform apply -input=false tfplan
rm -f tfplan

web_asg="$(terraform output -raw web_asg_name)"
app_asg="$(terraform output -raw app_asg_name)"
url="$(terraform output -raw app_url)"

bash "${repo_root}/deploy/ec2/wait-for-refresh.sh" "${app_asg}" "${web_asg}"
bash "${repo_root}/tests/smoke/smoke_test.sh" "${url}" "${version}"

# The release passed its checks: record it as the deployed version.
aws ssm put-parameter --name "/cloudbatch818-three-tier/${env}/deployed-version" \
  --type String --overwrite --value "${version}" >/dev/null
