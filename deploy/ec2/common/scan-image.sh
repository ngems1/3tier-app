#!/bin/bash
# Scans the image being baked with Trivy, just before it is saved as an AMI:
# Amazon Linux packages plus the application's installed dependencies (the
# FastAPI virtualenv on the app image). The build fails on CRITICAL
# vulnerabilities that have a fix available; HIGH ones are reported only.
# Trivy is installed from Aqua Security's signed RPM repository and removed
# again afterwards, so it isn't part of the AMI.
#
# Set TRIVY_SCAN=false (Packer variable security_scan=false) to skip it in an
# emergency.
set -euo pipefail

if [ "${TRIVY_SCAN:-true}" != "true" ]; then
  echo "==> Trivy image scan SKIPPED (security_scan=false)"
  exit 0
fi

echo "==> Installing Trivy (temporary)"
cat > /etc/yum.repos.d/trivy.repo <<'REPO'
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key
REPO
dnf -y install trivy

cache=/tmp/trivy-cache
cleanup() {
  dnf -y remove trivy >/dev/null 2>&1 || true
  rm -f /etc/yum.repos.d/trivy.repo
  rm -rf "${cache}"
}
trap cleanup EXIT

echo "==> Downloading the vulnerability database"
for attempt in 1 2 3 4 5; do
  if trivy image --download-db-only --cache-dir "${cache}" --quiet; then
    break
  fi
  if [ "${attempt}" = 5 ]; then
    echo "Could not download the Trivy database after 5 attempts" >&2
    exit 1
  fi
  echo "Database download failed (attempt ${attempt}/5); retrying in 20 s"
  sleep 20
done

scan() {
  trivy rootfs --cache-dir "${cache}" --skip-db-update --skip-java-db-update \
    --scanners vuln --ignore-unfixed --no-progress \
    --skip-dirs /proc --skip-dirs /sys --skip-dirs /dev --skip-dirs /run \
    --skip-dirs "${cache}" "$@" /
}

echo "==> Vulnerabilities in this image (HIGH and CRITICAL, fix available)"
scan --severity HIGH,CRITICAL --exit-code 0

echo "==> Gate: fail the build on CRITICAL vulnerabilities with a fix"
if ! scan --severity CRITICAL --exit-code 1 --quiet --format table >/dev/null; then
  echo "CRITICAL vulnerabilities with an available fix were found (see the table above)." >&2
  echo "Update the affected packages or dependencies and rebuild." >&2
  exit 1
fi
echo "==> Trivy: no CRITICAL vulnerabilities with an available fix"
