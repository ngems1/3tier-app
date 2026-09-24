#!/bin/bash
# Usage: configure-cloudwatch.sh <config-template> <metrics-namespace> <log-group>
# Renders the baked CloudWatch Agent config for this environment and starts
# the agent (memory/disk metrics per ASG + application logs).
set -euo pipefail

template="$1"
namespace="$2"
log_group="$3"
config=/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

sed -e "s#__NAMESPACE__#${namespace}#g" -e "s#__LOG_GROUP__#${log_group}#g" "${template}" > "${config}"
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c "file:${config}"
