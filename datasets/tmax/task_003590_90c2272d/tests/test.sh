#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
import pytest

SCRIPT = "/home/user/run_pipeline.sh"
EVENTS = "/home/user/logs/server_events.jsonl"
METADATA = "/home/user/data/user_metadata.csv"
REPORT = "/home/user/summary_report.json"

CANONICAL_EVENTS = [
    '{"user_id": 101, "event_type": "login", "timestamp": "2023-10-01T10:00:00Z"}',
    '{"user_id": 102, "event_type": "click", "timestamp": "2023-10-01T10:05:00Z", "payload": "bad \\u00XX data"}',
    '{"user_id": 101, "event_type": "purchase", "timestamp": "2023-10-01T10:10:00Z"}',
    '{"user_id": 103, "timestamp": "2023-10-01T10:15:00Z"}',
    '{"user_id": 104, "event_type": "login", "timestamp": "2023-10-01T10:20:00Z"}',
    '{"user_id": 102, "event_type": "login", "timestamp": "2023-10-01T10:25:00Z", "note": "good \\u0032 unicode"}',
    '{"user_id": 101, "event_type": "click", "timestamp": "2023-10-01T10:30:00Z"}',
    '{"user_id": 104, "event_type": "purchase", "timestamp": "2023-10-01T10:35:00Z"}',
]

CANONICAL_METADATA = [
    ["user_id", "region"],
    [101, "NA"],
    [102, "EU"],
    [103, "APAC"],
    [104, "EU"],
]

EXPECTED_CANONICAL = {
    "NA": {"login": 1, "purchase": 1, "click": 1},
    "EU": {"login": 2, "purchase": 1},
}


def write_inputs(lines, metadata_rows):
    with open(EVENTS, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(METADATA, "w", encoding="utf-8", newline="") as f:
        csv.writer(f).writerows(metadata_rows)


def write_canonical_inputs():
    write_inputs(CANONICAL_EVENTS, CANONICAL_METADATA)


def run_pipeline():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        [SCRIPT], capture_output=True, text=True, timeout=20, cwd="/home/user"
    )
    assert result.returncode == 0, (
        f"Pipeline exited with {result.returncode}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(REPORT), f"Output file {REPORT} is missing after running the pipeline."
    try:
        with open(REPORT, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{REPORT} does not contain valid JSON.")


def test_run_pipeline_script_exists_and_executable():
    """Test that the run_pipeline.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_summary_report_exists_and_correct():
    """Execute the pipeline on the supplied data and check its exact aggregation."""
    write_canonical_inputs()
    data = run_pipeline()
    assert data == EXPECTED_CANONICAL, (
        f"The contents of {REPORT} do not match the expected aggregated statistics."
    )


def test_pipeline_processes_changed_inputs_and_rejects_invalid_records():
    """Ensure the executable derives its output from both inputs rather than emitting a fixed report."""
    token = secrets.token_hex(6)
    uid1 = secrets.randbelow(1000000) + 2000000
    uid2 = uid1 + 1
    uid3 = uid1 + 2
    unknown_uid = uid1 + 999
    region1 = "R1_" + token
    region2 = "R2_" + token
    region3 = "R3_" + token
    event1 = "evtA_" + token
    event2 = "evtB_" + token
    event3 = "evtC_" + token

    lines = [
        json.dumps({"user_id": uid1, "event_type": event1}),
        json.dumps({"user_id": uid1, "event_type": event1, "extra": "ok"}),
        json.dumps({"user_id": uid1, "event_type": event2}),
        json.dumps({"user_id": uid2, "event_type": event1}),
        json.dumps({"user_id": uid3, "event_type": event3}),
        json.dumps({"user_id": uid2, "event_type": event2, "note": "good unicode 2"}),
        '{"user_id": %d, "event_type": "%s", "payload": "bad \\u00ZZ"}' % (uid2, event3),
        json.dumps({"user_id": uid1}),
        json.dumps({"user_id": str(uid1), "event_type": event1}),
        json.dumps({"user_id": uid1, "event_type": 42}),
        json.dumps({"user_id": unknown_uid, "event_type": event1}),
        json.dumps([{"user_id": uid1, "event_type": event1}]),
        "null",
        "not json at all",
    ]
    metadata = [
        ["user_id", "region"],
        [uid1, region1],
        [uid2, region2],
        [uid3, region3],
    ]
    expected = {
        region1: {event1: 2, event2: 1},
        region2: {event1: 1, event2: 1},
        region3: {event3: 1},
    }

    try:
        write_inputs(lines, metadata)
        data = run_pipeline()
        assert data == expected, (
            "Pipeline did not correctly process the verifier-generated inputs; "
            f"expected {expected!r}, got {data!r}."
        )
    finally:
        write_canonical_inputs()
        if os.path.isfile(SCRIPT) and os.access(SCRIPT, os.X_OK):
            restored = run_pipeline()
            assert restored == EXPECTED_CANONICAL


def test_crontab_configured_correctly():
    """Test that the crontab is configured to run the script at the top of every hour."""
    try:
        result = subprocess.run(
            ["crontab", "-l"], capture_output=True, text=True, check=True
        )
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it installed for the current user?")

    cron_lines = [
        line.strip()
        for line in crontab_output.splitlines()
        if line.strip() and not line.startswith("#")
    ]

    found = False
    for line in cron_lines:
        if SCRIPT in line:
            parts = line.split()
            if len(parts) >= 5:
                schedule = " ".join(parts[:5])
                if schedule == "0 * * * *":
                    found = True
                    break

    assert found, (
        "Crontab does not contain the expected schedule '0 * * * *' "
        f"for {SCRIPT}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
