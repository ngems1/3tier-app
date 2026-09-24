#!/usr/bin/env bash
# Waits for every ECS service of one environment to finish rolling out the
# task definition that Terraform just registered.
#   verify-deployment.sh <terraform-environment-dir>
#
# Exits non-zero if a deployment failed or the deployment circuit breaker
# rolled a service back to its previous task definition (new tasks kept
# failing to start or to pass their health checks).
set -euo pipefail

tf_dir="$1"
timeout_seconds="${DEPLOY_TIMEOUT_SECONDS:-1800}"

cluster="$(terraform -chdir="${tf_dir}" output -raw cluster_name)"
services="$(terraform -chdir="${tf_dir}" output -json service_names)"
expected_task_definitions="$(terraform -chdir="${tf_dir}" output -json task_definition_arns)"

for key in $(jq -r 'keys[]' <<<"${services}"); do
  service="$(jq -r --arg k "${key}" '.[$k]' <<<"${services}")"
  expected="$(jq -r --arg k "${key}" '.[$k]' <<<"${expected_task_definitions}")"
  echo "Waiting for ${service} to run ${expected##*/}"
  deadline=$(( $(date +%s) + timeout_seconds ))

  while true; do
    description="$(aws ecs describe-services --cluster "${cluster}" --services "${service}" \
      --query 'services[0]' --output json)"
    primary="$(jq -c '.deployments[] | select(.status == "PRIMARY")' <<<"${description}")"
    task_definition="$(jq -r '.taskDefinition' <<<"${primary}")"
    rollout="$(jq -r '.rolloutState // "UNKNOWN"' <<<"${primary}")"
    running="$(jq -r '.runningCount' <<<"${primary}")"
    desired="$(jq -r '.desiredCount' <<<"${primary}")"
    deployments="$(jq '.deployments | length' <<<"${description}")"
    echo "  ${service}: ${rollout}, ${running}/${desired} tasks, ${deployments} deployment(s)"

    if [ "${task_definition}" != "${expected}" ]; then
      echo "${service} is running ${task_definition##*/} instead of ${expected##*/}: the deployment circuit breaker rolled it back." >&2
      jq -r '.events[:10][] | "  \(.createdAt) \(.message)"' <<<"${description}" >&2
      exit 1
    fi

    case "${rollout}" in
      COMPLETED)
        if [ "${deployments}" -eq 1 ] && [ "${running}" -eq "${desired}" ]; then
          break
        fi ;;
      FAILED)
        echo "Deployment of ${service} failed." >&2
        jq -r '.events[:10][] | "  \(.createdAt) \(.message)"' <<<"${description}" >&2
        exit 1 ;;
    esac

    if (( $(date +%s) > deadline )); then
      echo "Timed out waiting for ${service}" >&2
      exit 1
    fi
    sleep 15
  done
done
echo "All ECS services are running the new release."
