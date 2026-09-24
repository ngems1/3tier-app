#!/bin/bash
# Installs the FastAPI release into the app image. Runs at bake time only.
set -euo pipefail

echo "==> Installing Python 3.11"
dnf -y install python3.11 python3.11-pip

echo "==> Creating the service account"
useradd --system --no-create-home --shell /sbin/nologin threetier
chown root:threetier /var/log/three-tier
chmod 0775 /var/log/three-tier

echo "==> Installing release ${APP_VERSION}"
install -d -m 0755 /opt/three-tier/backend
cp -r /tmp/build/release/app /opt/three-tier/backend/app
install -m 0644 /tmp/build/requirements.txt /opt/three-tier/backend/requirements.txt
python3.11 -m venv /opt/three-tier/backend/venv
/opt/three-tier/backend/venv/bin/pip install --no-cache-dir --disable-pip-version-check \
  -r /opt/three-tier/backend/requirements.txt
chown -R root:root /opt/three-tier/backend
chmod -R go-w /opt/three-tier/backend

echo "==> RDS CA bundle (TLS to the database)"
install -d -m 0755 /etc/pki/rds
curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /etc/pki/rds/global-bundle.pem
chmod 0644 /etc/pki/rds/global-bundle.pem

echo "==> Service, logging and monitoring config"
install -m 0644 /tmp/build/three-tier-backend.service /etc/systemd/system/three-tier-backend.service
install -m 0644 /tmp/build/logrotate.conf /etc/logrotate.d/three-tier
install -m 0644 /tmp/build/cloudwatch-agent.json /opt/three-tier/cloudwatch/app.json
systemctl daemon-reload

echo "==> Verifying the release imports cleanly"
cd /opt/three-tier/backend && ./venv/bin/python -c "import app.main"
