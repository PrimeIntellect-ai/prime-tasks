#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_pipeline.py
import csv
import gzip
import json
import os
import secrets
import subprocess
from collections import Counter

SCRIPT = "/home/user/process_data.sh"
RAW = "/home/user/raw_events.jsonl"
CLEANED = "/home/user/cleaned_data.jsonl"
ARCHIVE = "/home/user/archive/cleaned_data.jsonl.gz"
SUMMARY = "/home/user/summary.csv"
LOG = "/home/user/pipeline.log"

ORIGINAL = r'''{"event_id": "e1", "user_id": "u1", "email": "bob@domain.com", "event_type": "click", "timestamp": "2023-01-01T10:00:00Z", "message": "hello"}
{"event_id": "e2", "user_id": "u2", "email": "alice@domain.com", "event_type": "view", "timestamp": "2023-01-01T10:05:00Z", "message": "bad \uZZZZ string"}
{"event_id": "e1", "user_id": "u1", "email": "bob@domain.com", "event_type": "click", "timestamp": "2023-01-01T09:55:00Z", "message": "hello older"}
{"event_id": "e3", "user_id": "u3", "email": "charlie@test.org", "event_type": "purchase", "timestamp": "2023-01-01T10:10:00Z", "message": "ok"}
{"event_id": "e4", "user_id": "u4", "email": "dave@test.org", "event_type": "view", "timestamp": "2023-01-01T10:15:00Z", "message": "syntax error"
{"event_id": "e3", "user_id": "u3", "email": "charlie@test.org", "event_type": "purchase", "timestamp": "2023-01-01T10:12:00Z", "message": "ok later duplicate"}
'''


def run_script():
    result = subprocess.run(
        ["/bin/bash", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_jsonl(path):
    assert os.path.isfile(path), f"File {path} does not exist"
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().strip().split("\n")
    assert lines != [""], f"File {path} is empty"
    parsed = []
    for line in lines:
        try:
            parsed.append(json.loads(line))
        except json.JSONDecodeError:
            assert False, f"Line in {path} is not valid JSON: {line}"
    return lines, parsed


def check_original_assertions():
    lines, parsed = load_jsonl(CLEANED)
    assert len(lines) == 3, f"Expected 3 lines in {CLEANED}, found {len(lines)}"

    for record in parsed:
        email = record.get("email")
        if email:
            assert email.startswith("***@"), f"Email not anonymized correctly: {email}"
        message = record.get("message", "")
        assert "\\uZZZZ" not in message, "Found unredacted \\uZZZZ"
        if record.get("event_id") == "e2":
            assert "[REDACTED]" in message, "Message did not contain [REDACTED]"

    e1_records = [r for r in parsed if r["event_id"] == "e1"]
    assert len(e1_records) == 1, "Duplicate e1 found"
    assert e1_records[0]["timestamp"] == "2023-01-01T09:55:00Z", "Did not keep oldest e1"

    e3_records = [r for r in parsed if r["event_id"] == "e3"]
    assert len(e3_records) == 1, "Duplicate e3 found"
    assert e3_records[0]["timestamp"] == "2023-01-01T10:10:00Z", "Did not keep oldest e3"

    assert os.path.isfile(ARCHIVE), f"Archive {ARCHIVE} does not exist"
    try:
        with gzip.open(ARCHIVE, "rt", encoding="utf-8") as f:
            content = f.read()
            assert len(content) > 0, "Gzip file is empty"
    except Exception as exc:
        assert False, f"Failed to read gzip file {ARCHIVE}: {exc}"

    assert os.path.isfile(SUMMARY), f"File {SUMMARY} does not exist"
    with open(SUMMARY, "r", encoding="utf-8") as f:
        summary_lines = f.read().strip().split("\n")
    assert len(summary_lines) == 4, f"Expected 4 lines in {SUMMARY}, found {len(summary_lines)}"
    assert summary_lines[0] == "event_type,count", "Incorrect CSV header"
    assert summary_lines[1] == "click,1", "Incorrect count for click"
    assert summary_lines[2] == "purchase,1", "Incorrect count for purchase"
    assert summary_lines[3] == "view,1", "Incorrect count for view"

    assert os.path.isfile(LOG), f"File {LOG} does not exist"
    with open(LOG, "r", encoding="utf-8") as f:
        log_lines = f.read().strip().split("\n")
    assert len(log_lines) == 3, f"Expected 3 lines in {LOG}, found {len(log_lines)}"
    assert "Total raw lines: 6" in log_lines[0], "Incorrect total raw lines"
    assert "Valid parsed lines: 5" in log_lines[1], "Incorrect valid parsed lines"
    assert "Final deduplicated lines: 3" in log_lines[2], "Incorrect final deduplicated lines"


def write_dynamic_fixture():
    nonce = secrets.token_hex(8)
    ids = {name: f"{name}_{nonce}" for name in ("alpha", "beta", "gamma", "delta")}
    types = {
        "alpha": f"click_{nonce}",
        "beta": f"view_{nonce}",
        "gamma": f"purchase_{nonce}",
        "delta": f"audit_{nonce}",
    }

    records = [
        {"event_id": ids["alpha"], "user_id": f"u1_{nonce}", "email": f"new.{nonce}@one.example", "event_type": types["alpha"], "timestamp": "2041-06-01T12:00:00Z", "message": f"newer {nonce}", "extra": {"keep": 1}},
        {"event_id": ids["alpha"], "user_id": f"u1_{nonce}", "email": f"old.{nonce}@one.example", "event_type": types["alpha"], "timestamp": "2041-06-01T08:00:00Z", "message": f"oldest {nonce}", "extra": {"keep": 2}},
        {"event_id": ids["beta"], "user_id": f"u2_{nonce}", "email": f"person.{nonce}@two.example", "event_type": types["beta"], "timestamp": "2041-06-02T09:00:00Z", "message": f"bad __BAD__ middle __BAD__ {nonce}", "number": 37},
        {"event_id": ids["gamma"], "user_id": f"u3_{nonce}", "email": None, "event_type": types["gamma"], "timestamp": "2041-06-03T09:00:00Z", "message": f"null email {nonce}"},
        {"event_id": ids["delta"], "user_id": f"u4_{nonce}", "event_type": types["delta"], "timestamp": "2041-06-04T09:00:00Z", "message": f"missing email {nonce}", "flag": True},
        {"event_id": ids["beta"], "user_id": f"u2_{nonce}", "email": f"later.{nonce}@two.example", "event_type": types["beta"], "timestamp": "2041-06-05T09:00:00Z", "message": f"later duplicate {nonce}"},
    ]

    raw_lines = []
    for record in records:
        line = json.dumps(record, separators=(",", ":"), ensure_ascii=False)
        line = line.replace("__BAD__", r"\uZZZZ")
        raw_lines.append(line)
    raw_lines.insert(4, '{"event_id":"broken_' + nonce + '","message":"unterminated"')

    with open(RAW, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(raw_lines) + "\n")

    expected = []
    for record in records:
        fixed = json.loads(json.dumps(record))
        fixed["message"] = fixed["message"].replace("__BAD__", "[REDACTED]")
        if fixed.get("email") is not None:
            fixed["email"] = "***@" + fixed["email"].split("@", 1)[1]
        expected.append(fixed)

    deduped = {}
    for record in expected:
        event_id = record["event_id"]
        if event_id not in deduped or record["timestamp"] < deduped[event_id]["timestamp"]:
            deduped[event_id] = record
    return list(deduped.values()), len(raw_lines), len(records)


def check_dynamic_results(expected, raw_count, valid_count):
    lines, actual = load_jsonl(CLEANED)
    assert len(lines) == len(expected), "Incorrect final deduplicated line count"
    assert all(isinstance(record, dict) for record in actual), "Every output line must be a JSON object"

    actual_by_id = {record.get("event_id"): record for record in actual}
    expected_by_id = {record["event_id"]: record for record in expected}
    assert len(actual_by_id) == len(actual), "Output contains duplicate event_id values"
    assert actual_by_id == expected_by_id, "Cleaned output does not fully match the transformed input"

    with open(CLEANED, "rb") as f:
        cleaned_bytes = f.read()
    assert os.path.isfile(ARCHIVE), f"Archive {ARCHIVE} does not exist"
    with gzip.open(ARCHIVE, "rb") as f:
        archived_bytes = f.read()
    assert archived_bytes == cleaned_bytes, "Archive does not contain the exact cleaned_data.jsonl"

    counts = Counter(record["event_type"] for record in expected)
    expected_summary = ["event_type,count"] + [f"{kind},{counts[kind]}" for kind in sorted(counts)]
    assert os.path.isfile(SUMMARY), f"File {SUMMARY} does not exist"
    with open(SUMMARY, "r", encoding="utf-8") as f:
        actual_summary = f.read().strip().splitlines()
    assert actual_summary == expected_summary, "Summary is not derived from the final dataset or is not sorted"

    expected_log = [
        f"Total raw lines: {raw_count}",
        f"Valid parsed lines: {valid_count}",
        f"Final deduplicated lines: {len(expected)}",
    ]
    assert os.path.isfile(LOG), f"File {LOG} does not exist"
    with open(LOG, "r", encoding="utf-8") as f:
        actual_log = f.read().strip().splitlines()
    assert actual_log == expected_log, "Pipeline log does not contain the exact derived counts"


def main():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist"
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable"

    with open(RAW, "w", encoding="utf-8", newline="\n") as f:
        f.write(ORIGINAL)
    run_script()
    check_original_assertions()

    expected, raw_count, valid_count = write_dynamic_fixture()
    run_script()
    check_dynamic_results(expected, raw_count, valid_count)


if __name__ == "__main__":
    main()
PYTEST

if python3 /tmp/test_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
