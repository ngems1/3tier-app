"""Unit tests for the CloudWatch alarm -> Slack Lambda (no AWS or network)."""

import json

import alarm_to_slack as fn


def alarm(state="ALARM", old="OK", name="cloudbatch818-three-tier-prod-no-healthy-hosts"):
    return {
        "AlarmName": name,
        "AlarmDescription": "No healthy app targets",
        "NewStateValue": state,
        "OldStateValue": old,
        "NewStateReason": "Threshold Crossed: 1 datapoint [0.0] was less than the threshold (1.0).",
    }


def sns_event(*messages):
    return {"Records": [{"Sns": {"Subject": "ALARM", "Message": m}} for m in messages]}


def test_alarm_message_has_state_stack_name_reason_and_link():
    text = fn.format_message(alarm(), "EC2 prod", "us-east-1")
    assert text.startswith(":red_circle: *ALARM* (was OK) · *EC2 prod* · `cloudbatch818-three-tier-prod-no-healthy-hosts`")
    assert "> Threshold Crossed" in text
    assert "No healthy app targets" in text
    assert "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#alarmsV2:alarm/cloudbatch818-three-tier-prod-no-healthy-hosts|Open in CloudWatch>" in text


def test_recovery_is_green():
    text = fn.format_message(alarm(state="OK", old="ALARM"), "ECS dev", "us-east-1")
    assert text.startswith(":large_green_circle: *OK - recovered* (was ALARM) · *ECS dev*")


def test_every_record_is_posted(monkeypatch):
    posted = []
    monkeypatch.setattr(fn, "_webhook_url", lambda: "https://hooks.slack.com/services/T/B/X")
    monkeypatch.setattr(fn, "_post", lambda url, text: posted.append((url, text)))
    monkeypatch.setenv("STACK_LABEL", "EC2 dev")

    result = fn.handler(sns_event(json.dumps(alarm()), json.dumps(alarm(state="OK", old="ALARM"))))

    assert result == {"sent": 2}
    assert [t.split(" ")[0] for _, t in posted] == [":red_circle:", ":large_green_circle:"]
    assert all("*EC2 dev*" in t for _, t in posted)


def test_plain_text_sns_messages_are_still_forwarded(monkeypatch):
    posted = []
    monkeypatch.setattr(fn, "_webhook_url", lambda: "https://hooks.slack.com/services/T/B/X")
    monkeypatch.setattr(fn, "_post", lambda url, text: posted.append(text))

    assert fn.handler(sns_event("hello from a test publish")) == {"sent": 1}
    assert "hello from a test publish" in posted[0]


def test_does_nothing_until_the_webhook_is_configured(monkeypatch):
    monkeypatch.setattr(fn, "_webhook_url", lambda: "")
    monkeypatch.setattr(fn, "_post", lambda url, text: (_ for _ in ()).throw(AssertionError("must not post")))

    assert fn.handler(sns_event(json.dumps(alarm()))) == {"sent": 0}
