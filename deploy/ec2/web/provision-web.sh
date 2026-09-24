#!/bin/bash
# Installs Nginx and the versioned React build into the web image.
set -euo pipefail

echo "==> Installing Nginx"
dnf -y install nginx gettext

echo "==> Installing release ${APP_VERSION}"
install -d -m 0755 /usr/share/nginx/three-tier /opt/three-tier/web
cp -r /tmp/build/release/. /usr/share/nginx/three-tier/
chown -R root:root /usr/share/nginx/three-tier
test -f /usr/share/nginx/three-tier/index.html

echo "==> Nginx and monitoring config"
install -m 0644 /tmp/build/nginx.conf /etc/nginx/nginx.conf
install -m 0644 /tmp/build/site.conf.template /opt/three-tier/web/site.conf.template
install -m 0755 /tmp/build/render-nginx.sh /opt/three-tier/bin/render-nginx.sh
install -m 0644 /tmp/build/cloudwatch-agent.json /opt/three-tier/cloudwatch/web.json

# Validate the config with a placeholder upstream; the real one is set at boot.
APP_ALB_DNS=internal-placeholder.example envsubst '${APP_ALB_DNS}'   < /opt/three-tier/web/site.conf.template > /etc/nginx/conf.d/three-tier.conf
nginx -t
rm -f /etc/nginx/conf.d/three-tier.conf
