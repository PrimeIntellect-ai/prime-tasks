#!/bin/bash
set -u
mkdir -p /logs/verifier
export PATH="/root/.cargo/bin:/home/user/.cargo/bin:${PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import subprocess
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

import pytest

PROJECT = "/home/user/config_tracker"
INPUT = os.path.join(PROJECT, "input.jsonl")
OUTPUT = os.path.join(PROJECT, "output.jsonl")
BINARY = os.path.join(PROJECT, "target", "debug", "config_tracker")


def test_output_jsonl_exists_and_correct():
    output_path = "/home/user/config_tracker/output.jsonl"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing. Did the Rust program run successfully?"

    with open(output_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 valid entries in output.jsonl, but found {len(lines)}."

    try:
        entry1 = json.loads(lines[0])
        entry2 = json.loads(lines[1])
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse lines in output.jsonl as JSON: {e}")

    assert entry1.get("server_id") == "srv-3", f"Expected first entry server_id to be 'srv-3', got '{entry1.get('server_id')}'"
    assert entry1.get("timestamp") == "2023-10-31T08:13:20Z", f"Expected first entry timestamp to be '2023-10-31T08:13:20Z', got '{entry1.get('timestamp')}'"
    assert entry1.get("description") == "Mise à jour du réseau", "Incorrect description for the first entry"

    payload1 = entry1.get("config_payload")
    assert isinstance(payload1, str), "config_payload must be a string"
    assert json.loads(payload1) == {"port": 8080}, "Incorrect config_payload content for the first entry"

    assert entry2.get("server_id") == "srv-6", f"Expected second entry server_id to be 'srv-6', got '{entry2.get('server_id')}'"
    assert entry2.get("timestamp") == "2023-11-01T14:46:40Z", f"Expected second entry timestamp to be '2023-11-01T14:46:40Z', got '{entry2.get('timestamp')}'"
    assert entry2.get("description") == "Add new cache node", "Incorrect description for the second entry"

    payload2 = entry2.get("config_payload")
    assert isinstance(payload2, str), "config_payload must be a string"
    assert json.loads(payload2) == {"cache": "redis"}, "Incorrect config_payload content for the second entry"


def aligned_timestamp(value):
    if isinstance(value, int) and not isinstance(value, bool):
        dt = datetime.fromtimestamp(value, tz=timezone.utc)
    else:
        dt = parsedate_to_datetime(value)
        if dt.tzinfo is None:
            raise ValueError("RFC 2822 timestamp lacks an offset")
        dt = dt.astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def expected_output(records):
    selected = {}
    for index, record in enumerate(records):
        description = record["description"]
        if len(description) > 40:
            continue
        try:
            payload = json.loads(record["config_payload"])
        except (TypeError, json.JSONDecodeError):
            continue
        if not isinstance(payload, dict):
            continue

        timestamp = aligned_timestamp(record["timestamp"])
        digest = hashlib.sha256(
            (description + record["config_payload"]).encode("utf-8")
        ).hexdigest()
        candidate = (timestamp, index, {
            "server_id": record["server_id"],
            "timestamp": timestamp,
            "description": description,
            "config_payload": record["config_payload"],
        })
        if digest not in selected or candidate[:2] < selected[digest][:2]:
            selected[digest] = candidate

    return [item[2] for item in sorted(selected.values(), key=lambda item: (item[0], item[1]))]


def test_compiled_application_processes_unseen_input():
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "src/main.rs is missing"
    assert os.path.isfile(BINARY), "The Rust application was not compiled"

    token = secrets.token_hex(6)
    common_description = f"network-{token}"
    common_payload = json.dumps({"port": secrets.randbelow(50000) + 10000}, separators=(",", ":"))
    concat_prefix = f"join-{token}"

    records = [
        {"server_id": f"late-{token}", "timestamp": 1700000300, "description": common_description, "config_payload": common_payload},
        {"server_id": f"boundary-{token}", "timestamp": "Wed, 15 Nov 2023 01:13:20 +0300", "description": "é" * 40, "config_payload": json.dumps({"unicode": token}, separators=(",", ":"))},
        {"server_id": f"too-long-{token}", "timestamp": 1699999900, "description": "界" * 41, "config_payload": "{\"valid\":true}"},
        {"server_id": f"early-{token}", "timestamp": "Tue, 14 Nov 2023 17:15:00 -0500", "description": common_description, "config_payload": common_payload},
        {"server_id": f"tie-later-{token}", "timestamp": 1700000100, "description": common_description, "config_payload": common_payload},
        {"server_id": f"malformed-{token}", "timestamp": 1700000050, "description": f"bad-{token}", "config_payload": "{bad json"},
        {"server_id": f"array-{token}", "timestamp": 1700000060, "description": f"array-{token}", "config_payload": "[1,2,3]"},
        {"server_id": f"concat-late-{token}", "timestamp": 1700000190, "description": concat_prefix, "config_payload": " {\"joined\":true}"},
        {"server_id": f"concat-early-{token}", "timestamp": 1700000150, "description": concat_prefix + " ", "config_payload": "{\"joined\":true}"},
        {"server_id": f"unique-{token}", "timestamp": 1700000200, "description": f"cache-{token}", "config_payload": json.dumps({"cache": token}, separators=(",", ":"))},
    ]
    expected = expected_output(records)

    with open(INPUT, "rb") as f:
        original_input = f.read()
    original_output = None
    if os.path.exists(OUTPUT):
        with open(OUTPUT, "rb") as f:
            original_output = f.read()

    try:
        with open(INPUT, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")

        completed = subprocess.run(
            [BINARY], cwd=PROJECT, text=True, capture_output=True, timeout=20
        )
        assert completed.returncode == 0, (
            f"Compiled application failed on unseen input. stdout={completed.stdout!r}, "
            f"stderr={completed.stderr!r}"
        )
        assert os.path.isfile(OUTPUT), "Application did not create output.jsonl"

        with open(OUTPUT, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
        try:
            actual = [json.loads(line) for line in lines]
        except json.JSONDecodeError as exc:
            pytest.fail(f"Application emitted invalid JSONL: {exc}")

        assert actual == expected, f"Incorrect processing of unseen input. Expected {expected!r}, got {actual!r}"
        assert all(set(entry) == {"server_id", "timestamp", "description", "config_payload"} for entry in actual)
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

score=0
if (
    cd /home/user/config_tracker &&
    cargo build --quiet &&
    cargo run --quiet &&
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
); then
    score=1
fi
echo "$score" > /logs/verifier/reward.txt
