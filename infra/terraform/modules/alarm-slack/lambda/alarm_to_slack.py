"""Forward CloudWatch alarm notifications from SNS to Slack.

Subscribed to an environment's alarm topic. For every alarm state change it
posts one message to the Slack incoming webhook stored (encrypted) in SSM
Parameter Store. The deploy pipeline writes that parameter from the
SLACK_WEBHOOK_URL GitHub secret; when it doesn't exist the function does
nothing, so the stack works without Slack.
"""

from __future__ import annotations

import json
import os
import urllib.parse
import urllib.request

STATE_STYLE = {
    "ALARM": (":red_circle:", "ALARM"),
    "OK": (":large_green_circle:", "OK - recovered"),
    "INSUFFICIENT_DATA": (":white_circle:", "INSUFFICIENT DATA"),
}

_webhook_cache: dict[str, str] = {}


def _webhook_url() -> str:
    """Webhook URL from SSM (cached per Lambda container); "" if not configured."""
    if "url" not in _webhook_cache:
        import boto3  # available in the Lambda runtime; imported lazily for tests

        ssm = boto3.client("ssm")
        try:
            value = ssm.get_parameter(Name=os.environ["WEBHOOK_PARAMETER"], WithDecryption=True)
            _webhook_cache["url"] = value["Parameter"]["Value"].strip()
        except ssm.exceptions.ParameterNotFound:
            _webhook_cache["url"] = ""
    return _webhook_cache["url"]


def format_message(alarm: dict, stack_label: str, region: str) -> str:
    """Slack mrkdwn text for one CloudWatch alarm notification."""
    name = alarm.get("AlarmName", "unknown alarm")
    state = alarm.get("NewStateValue", "UNKNOWN")
    previous = alarm.get("OldStateValue")
    reason = alarm.get("NewStateReason") or alarm.get("AlarmDescription") or ""
    emoji, label = STATE_STYLE.get(state, (":grey_question:", state))
    link = (
        f"https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}"
        f"#alarmsV2:alarm/{urllib.parse.quote(name, safe='')}"
    )
    change = f" (was {previous})" if previous and previous != state else ""
    where = f" · *{stack_label}*" if stack_label else ""
    lines = [f"{emoji} *{label}*{change}{where} · `{name}`"]
    if alarm.get("AlarmDescription") and alarm.get("AlarmDescription") != reason:
        lines.append(alarm["AlarmDescription"])
    if reason:
        lines.append(f"> {reason[:500]}")
    lines.append(f"<{link}|Open in CloudWatch>")
    return "\n".join(lines)


def _post(url: str, text: str) -> None:
    body = json.dumps({"text": text}).encode()
    request = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=10) as response:  # noqa: S310 - fixed https webhook
        response.read()


def handler(event: dict, context: object = None) -> dict:
    url = _webhook_url()
    if not url:
        print("Slack webhook parameter not set; skipping.")
        return {"sent": 0}

    stack_label = os.environ.get("STACK_LABEL", "")
    region = os.environ.get("AWS_REGION", "us-east-1")
    sent = 0
    for record in event.get("Records", []):
        sns = record.get("Sns", {})
        message = sns.get("Message", "")
        try:
            alarm = json.loads(message)
        except ValueError:
            alarm = {"AlarmName": sns.get("Subject") or "SNS message", "NewStateReason": message}
        # A failed post raises, so Lambda retries the SNS delivery.
        _post(url, format_message(alarm, stack_label, region))
        sent += 1
    return {"sent": sent}
