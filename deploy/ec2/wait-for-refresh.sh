#!/usr/bin/env bash
# Waits for the latest instance refresh of each ASG to finish.
#   wait-for-refresh.sh <asg-name> [<asg-name> ...]
# Exits non-zero if a refresh failed, was cancelled or rolled back (the ASG
# rolls back automatically when new instances do not become healthy).
set -euo pipefail

timeout_seconds="${REFRESH_TIMEOUT_SECONDS:-2700}"

for asg in "$@"; do
  echo "Waiting for instance refresh on ${asg}"
  deadline=$(( $(date +%s) + timeout_seconds ))
  while true; do
    status="$(aws autoscaling describe-instance-refreshes \
      --auto-scaling-group-name "${asg}" --max-records 1 \
      --query 'InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]' --output text)"
    state="$(cut -f1 <<<"${status}")"
    echo "  ${asg}: ${status}"
    case "${state}" in
      Successful|None)
        break ;;
      Pending|InProgress|Baking|Cancelling|RollbackInProgress)
        ;;
      *)
        echo "Instance refresh for ${asg} ended with status ${state}" >&2
        exit 1 ;;
    esac
    if (( $(date +%s) > deadline )); then
      echo "Timed out waiting for ${asg}" >&2
      exit 1
    fi
    sleep 20
  done
done
echo "All instance refreshes completed."
