#!/usr/bin/env bash
# Post-deployment smoke test, run by CI after every EC2 and ECS deploy (and by
# deploy/ec2/deploy.sh). Checks the public endpoint end to end:
#   EC2: ALB -> web tier -> internal ALB -> app tier -> RDS
#   ECS: ALB -> frontend service, and ALB /api/* -> backend service -> RDS
#
#   tests/smoke/smoke_test.sh https://dev.example.com [expected-version]
set -euo pipefail

base_url="${1:?usage: smoke_test.sh <base-url> [expected-version]}"
expected_version="${2:-}"
attempts="${SMOKE_ATTEMPTS:-20}"
fail=0

check() {
  local name="$1" url="$2" pattern="$3" body=""
  for ((i = 1; i <= attempts; i++)); do
    if body="$(curl -fsS --max-time 10 "${url}")" && grep -q "${pattern}" <<<"${body}"; then
      echo "PASS ${name}"
      return 0
    fi
    sleep 6
  done
  echo "FAIL ${name}: ${url} (last body: ${body:0:200})" >&2
  fail=1
}

# With a domain (https:// URL), plain HTTP must redirect to HTTPS. Without a
# domain yet, the app is served over HTTP only and this check is skipped.
if [[ "${base_url}" == https://* ]]; then
  http_url="${base_url/https:/http:}"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${http_url}/")"
  if [[ "${code}" == "301" ]]; then echo "PASS http->https redirect"; else echo "FAIL http->https redirect (got ${code})" >&2; fail=1; fi
else
  echo "SKIP http->https redirect (no domain configured yet)"
fi

check "web tier health"          "${base_url}/healthz"      "ok"
check "frontend served"          "${base_url}/"             "<div id=\"root\">"
check "api readiness (database)" "${base_url}/api/healthz"  '"database":"up"'
check "task list"                "${base_url}/api/tasks"    '^\['

if [[ -n "${expected_version}" ]]; then
  check "deployed version" "${base_url}/api/healthz" "\"version\":\"${expected_version}\""
fi

exit "${fail}"
