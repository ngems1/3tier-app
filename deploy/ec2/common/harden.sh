#!/bin/bash
# Base hardening shared by the web and app images (Amazon Linux 2023).
set -euo pipefail

echo "==> Applying the latest Amazon Linux 2023 security updates"
dnf -y upgrade --releasever=latest

echo "==> Installing agents"
dnf -y install amazon-cloudwatch-agent amazon-ssm-agent audit logrotate
systemctl enable amazon-ssm-agent.service auditd.service

echo "==> Kernel network hardening"
cat > /etc/sysctl.d/90-three-tier-hardening.conf <<'SYSCTL'
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
SYSCTL

echo "==> Installing helper scripts"
install -d -m 0755 /opt/three-tier/bin /opt/three-tier/cloudwatch /var/log/three-tier
install -m 0755 /tmp/build/configure-cloudwatch.sh /opt/three-tier/bin/configure-cloudwatch.sh
echo "${APP_VERSION}" > /opt/three-tier/VERSION
