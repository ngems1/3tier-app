#!/bin/bash
# Renders the site config with this environment's internal app ALB and
# validates it. Called from the launch template user data.
set -euo pipefail

set -a
# shellcheck source=/dev/null
source /etc/three-tier/web.env
set +a

envsubst '${APP_ALB_DNS}' < /opt/three-tier/web/site.conf.template > /etc/nginx/conf.d/three-tier.conf
nginx -t
