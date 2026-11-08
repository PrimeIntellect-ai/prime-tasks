#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import subprocess
from collections import Counter
from datetime import datetime, timezone

import pytest

SCRIPT_PATH = "/home/user/process_logs.sh"
OUTPUT_PATH = "/home/user/stratified_sample.jsonl"
RAW_PATH = "/home/user/raw_logs.jsonl"


def remove_malformed_unicode_escapes(text):
    """Remove malformed JSON Unicode escapes while preserving surrounding text."""
    out = []
    i = 0
    hexdigits = set("0123456789abcdefABCDEF")
    while i < len(text):
        if text[i:i + 2] != r"\u":
            out.append(text[i])
            i += 1
            continue

        following = text[i + 2:i + 6]
        if len(following) == 4 and all(c in hexdigits for c in following):
            out.append(text[i:i + 6])
            i += 6
            continue

        # Drop the malformed introducer and the attempted hex digits. If an
        # alphanumeric invalid character occurs within the four-character
        # escape, it is part of the malformed escape as well.
        j = i + 2
        consumed = 0
        while j < len(text) and consumed < 4 and text[j] in hexdigits:
            j += 1
            consumed += 1
        if consumed < 4 and j < len(text) and text[j].isalnum():
            j += 1
        i = j
    return "".join(out)


def expected_records():
    records = []
    with open(RAW_PATH, "r", encoding="utf-8") as f:
        for line_number, raw_line in enumerate(f, 1):
            cleaned = remove_malformed_unicode_escapes(raw_line)
            try:
                source = json.loads(cleaned)
            except json.JSONDecodeError as exc:
                pytest.fail(f"Verifier could not clean source line {line_number}: {exc}")

            raw_ts = source["timestamp"]
            if isinstance(raw_ts, int) or (isinstance(raw_ts, str) and re.fullmatch(r"\d+", raw_ts)):
                timestamp = datetime.fromtimestamp(int(raw_ts), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            else:
                timestamp = datetime.strptime(raw_ts, "%d/%b/%Y:%H:%M:%S").replace(
                    tzinfo=timezone.utc
                ).strftime("%Y-%m-%dT%H:%M:%SZ")

            octets = source["ip_address"].split(".")
            assert len(octets) == 4
            masked_ip = ".".join(octets[:3] + ["0"])
            records.append({
                "timestamp": timestamp,
                "ip_address": masked_ip,
                "status": source["status"],
                "user_agent": source["user_agent"],
            })
    return records


@pytest.fixture(scope="session", autouse=True)
def run_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "rb") as f:
        script_bytes = f.read()
    assert b"\x00" not in script_bytes, "process_logs.sh is not a text shell script."
    script_text = script_bytes.decode("utf-8")
    first_line = script_text.splitlines()[0] if script_text.splitlines() else ""
    assert first_line.startswith("#!") and "bash" in first_line, "process_logs.sh must be a Bash script."

    active_lines = []
    for line in script_text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        active_lines.append(line.split("#", 1)[0])
    active_script = "\n".join(active_lines)
    uses_parallel = re.search(r"(^|[;&|]\s*|\b)parallel(?:\s|$)", active_script, re.MULTILINE)
    uses_xargs_p = re.search(
        r"\bxargs\b[^\n]*(?:-P(?:\d+|\s+\S+)|--max-procs(?:=\S+|\s+\S+))",
        active_script,
    )
    assert uses_parallel or uses_xargs_p, "Script must process records using GNU parallel or xargs -P."

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    try:
        result = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("process_logs.sh did not finish within 60 seconds.")
    assert result.returncode == 0, (
        f"process_logs.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_output_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."


def test_output_format_and_content():
    if not os.path.isfile(OUTPUT_PATH):
        pytest.fail(f"Output file {OUTPUT_PATH} does not exist.")

    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        lines = f.readlines()

    assert len(lines) > 0, f"Output file {OUTPUT_PATH} is empty."

    source_records = expected_records()
    available = Counter(
        (r["timestamp"], r["ip_address"], r["status"], r["user_agent"])
        for r in source_records
    )
    status_counts = {}
    output_records = Counter()

    for i, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {OUTPUT_PATH} is not valid JSON: {line.strip()}")

        expected_keys = {"timestamp", "ip_address", "status", "user_agent"}
        assert set(data.keys()) == expected_keys, f"Line {i+1} does not have exactly the required keys. Found: {list(data.keys())}"

        status = data["status"]
        assert isinstance(status, int) and not isinstance(status, bool), f"Status on line {i+1} must be an integer."
        status_counts[status] = status_counts.get(status, 0) + 1

        ip = data["ip_address"]
        assert isinstance(ip, str) and re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.0$", ip), f"IP address {ip} on line {i+1} is not masked properly (should end in .0)."

        ts = data["timestamp"]
        assert isinstance(ts, str) and re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", ts), f"Timestamp {ts} on line {i+1} is not in strict ISO 8601 UTC format."

        ua = data["user_agent"]
        assert isinstance(ua, str), f"user_agent on line {i+1} must be a string."
        assert r"\u" not in ua, f"Malformed unicode might still be present in user_agent on line {i+1}: {ua}"

        record_key = (ts, ip, status, ua)
        output_records[record_key] += 1
        assert output_records[record_key] <= available[record_key], (
            f"Line {i+1} is not the correctly cleaned and transformed form of any available source record: {data}"
        )

    # Preserve the original dataset-specific assertion.
    expected_statuses = {200, 404, 500}
    assert set(status_counts.keys()) == expected_statuses, f"Expected statuses {expected_statuses}, but found {set(status_counts.keys())}"

    # Also derive the required strata from the actual source file.
    source_statuses = {record["status"] for record in source_records}
    assert set(status_counts.keys()) == source_statuses, f"Expected source statuses {source_statuses}, but found {set(status_counts.keys())}"

    for status, count in status_counts.items():
        assert count == 3, f"Expected exactly 3 samples for status {status}, but found {count}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
