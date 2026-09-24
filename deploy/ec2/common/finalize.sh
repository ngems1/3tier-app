#!/bin/bash
# Last step of every image build: remove build-time access and leftovers.
# Instances are managed through SSM Session Manager only, so SSH is disabled.
set -euo pipefail

systemctl disable sshd.service
rm -f /home/ec2-user/.ssh/authorized_keys /root/.ssh/authorized_keys
dnf clean all
rm -rf /tmp/build /var/cache/dnf
cloud-init clean --logs
echo "==> Image finalized for release ${APP_VERSION}"
