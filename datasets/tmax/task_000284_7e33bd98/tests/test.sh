#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP="/tmp/log_extractor.verifier-backup"
cp -a /app/log_extractor "$BACKUP"
trap 'cp -a "$BACKUP" /app/log_extractor; rm -f "$BACKUP"' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import html
import json
import os
from pathlib import Path
import re
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
ENDPOINT = f"{BASE_URL}/audit"
AUTH_TOKEN = "Bearer sec-audit-2024"
AUTH_HEADERS = {"Authorization": AUTH_TOKEN}


def get_audit(headers=None):
    try:
        return requests.get(ENDPOINT, headers=headers, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to the server at {BASE_URL}. Is it running?")


def assert_json_response(response, expected):
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, (
        f"Expected Content-Type application/json, got {content_type}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert isinstance(data, list), f"Expected JSON response to be a list, got {type(data)}"
    assert len(data) == len(expected), (
        f"Expected {len(expected)} items in JSON array, got {len(data)}"
    )
    for i, expected_item in enumerate(expected):
        actual_item = data[i]
        assert actual_item.get("timestamp") == expected_item["timestamp"], (
            f"Mismatch in timestamp at index {i}. Expected {expected_item['timestamp']}, "
            f"got {actual_item.get('timestamp')}"
        )
        assert actual_item.get("user") == expected_item["user"], (
            f"Mismatch in user at index {i}. Expected {expected_item['user']}, "
            f"got {actual_item.get('user')}"
        )
        assert actual_item.get("event_data") == expected_item["event_data"], (
            f"Mismatch in event_data at index {i}. Expected {expected_item['event_data']}, "
            f"got {actual_item.get('event_data')}"
        )


def test_missing_auth_header():
    response = get_audit()
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized, got {response.status_code}. Response: {response.text}"
    )


def test_incorrect_auth_header():
    response = get_audit({"Authorization": "Bearer wrong-token"})
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized for incorrect token, got {response.status_code}. "
        f"Response: {response.text}"
    )


@pytest.mark.parametrize("value", [
    "Bearer sec-audit-2024 ",
    "bearer sec-audit-2024",
    "Bearer sec-audit-2024-extra",
])
def test_auth_header_must_match_exactly(value):
    response = get_audit({"Authorization": value})
    assert response.status_code == 401, (
        f"Expected 401 for non-exact Authorization value {value!r}, got "
        f"{response.status_code}. Response: {response.text}"
    )


def test_valid_request_processing():
    expected_data = [
        {
            "timestamp": "2024-01-01T10:00:00Z",
            "user": "admin",
            "event_data": "User viewed &lt;script&gt;alert(&#x27;XSS&#x27;)&lt;/script&gt;",
        },
        {
            "timestamp": "2024-01-01T10:05:00Z",
            "user": "hr_manager",
            "event_data": "Updated record for SSN [REDACTED_SSN] and [REDACTED_SSN].",
        },
    ]
    assert_json_response(get_audit(AUTH_HEADERS), expected_data)


def test_audit_is_the_only_exposed_endpoint():
    paths = ["/", "/health", "/audit/", "/not-an-endpoint-" + uuid.uuid4().hex]
    for path in paths:
        response = requests.get(BASE_URL + path, headers=AUTH_HEADERS, timeout=5)
        assert not (200 <= response.status_code < 300), (
            f"Unexpected successful GET endpoint {path}: status={response.status_code}, "
            f"response={response.text}"
        )

    response = requests.post(ENDPOINT, headers=AUTH_HEADERS, timeout=5)
    assert not (200 <= response.status_code < 300), (
        f"POST /audit must not be exposed; got {response.status_code}: {response.text}"
    )


def sanitized(events):
    result = []
    for event in events:
        item = dict(event)
        redacted = re.sub(r"\d{3}-\d{2}-\d{4}", "[REDACTED_SSN]", item["event_data"])
        item["event_data"] = html.escape(redacted, quote=True)
        result.append(item)
    return result


def install_extractor(events, marker, phase):
    encoded = [
        base64.b64encode(json.dumps(event).encode("utf-8")).decode("ascii")
        for event in events
    ]
    script = (
        "#!/usr/bin/env python3\n"
        "from pathlib import Path\n"
        f"with Path({str(marker)!r}).open('a') as f:\n"
        f"    f.write({phase!r} + '\\n')\n"
        f"for line in {encoded!r}:\n"
        "    print(line)\n"
    )
    Path("/app/log_extractor").write_text(script, encoding="utf-8")
    os.chmod("/app/log_extractor", 0o755)


def test_executes_and_processes_current_extractor_output_on_each_request(tmp_path):
    nonce = uuid.uuid4().hex
    marker = tmp_path / "extractor-invocations"
    cases = [
        [
            {
                "timestamp": f"dynamic-{nonce}-one",
                "user": f"user-{nonce[:8]}",
                "event_data": "Mix <b title=\"A&B\">'quoted'</b> SSN 123-45-6789 & tail",
            },
            {
                "timestamp": f"dynamic-{nonce}-two",
                "user": "second-user",
                "event_data": f"Two 000-00-0000 and 987-65-4321; nonce={nonce}",
            },
        ],
        [
            {
                "timestamp": f"changed-{nonce}",
                "user": "fresh-extractor-output",
                "event_data": f"<&\"' 321-54-9876 {nonce[::-1]}",
            }
        ],
    ]

    for index, events in enumerate(cases):
        phase = f"phase-{index}-{nonce}"
        install_extractor(events, marker, phase)
        response = get_audit(AUTH_HEADERS)
        assert_json_response(response, sanitized(events))
        assert marker.exists(), "The replacement /app/log_extractor was not executed"
        assert phase in marker.read_text(encoding="utf-8").splitlines(), (
            "The server did not execute the current /app/log_extractor for this request"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
