#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from collections import Counter

SUMMARY = "/home/user/backups/summary.log"
SOURCE = "/home/user/process_logs.go"
EXTRACTED = "/home/user/backups/extracted"
IPV4_PATTERN = re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')

EXPECTED_LOGS = {
    "app1.log": """[INFO] Application started
[DEBUG] Initializing modules

[ERROR] 2023-10-15T10:00:00Z
Database connection failed
Host: 10.0.0.5
Retrying in 5 seconds...

[INFO] Retry successful
""",
    "hidden.log": """[WARN] High memory usage
[ERROR] 2023-10-15T11:20:00Z
Unhandled exception in worker thread
NullReferenceException at processRequest
Client IP: 172.16.254.1
Stack trace ends.

[INFO] Shutting down
""",
    "regular.log": """[ERROR] Critical failure
Timeout reaching 192.168.100.22
""",
}

EXPECTED_ORIGINAL_RECORDS = [
    """[ERROR] 2023-10-15T10:00:00Z
Database connection failed
Host: [REDACTED]
Retrying in 5 seconds...""",
    """[ERROR] 2023-10-15T11:20:00Z
Unhandled exception in worker thread
NullReferenceException at processRequest
Client IP: [REDACTED]
Stack trace ends.""",
    """[ERROR] Critical failure
Timeout reaching [REDACTED]""",
]


def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def parse_summary(content):
    assert content, "summary.log is empty"
    assert "\r" not in content, "summary.log unexpectedly changed line endings"
    assert "\n\n\n" not in content, "Error records are separated by more than one empty line"

    body = content.rstrip("\n")
    trailing = len(content) - len(body)
    assert trailing <= 2, "summary.log has extra blank lines at the end"
    assert body, "summary.log contains no records"

    records = body.split("\n\n")
    assert all(records), "summary.log contains an empty record"
    for record in records:
        assert record.startswith("[ERROR]"), f"Record does not start with [ERROR]: {record!r}"
        assert "\n\n" not in record
    return records


def test_summary_log_exists():
    assert os.path.isfile(SUMMARY), "The file /home/user/backups/summary.log does not exist."


def test_go_script_exists():
    assert os.path.isfile(SOURCE), "The Go script /home/user/process_logs.go does not exist."


def test_extracted_files_exist():
    assert os.path.isdir(EXTRACTED), f"Directory {EXTRACTED} does not exist."

    # Keep the original extraction assertions and also verify complete contents.
    for filename, expected in EXPECTED_LOGS.items():
        path = os.path.join(EXTRACTED, filename)
        assert os.path.isfile(path), (
            f"Expected extracted file {path} is missing. "
            "Did you correctly identify and extract the hidden archives?"
        )
        assert read_text(path) == expected, f"Extracted file {path} has incorrect contents"


def test_summary_log_contents():
    content = read_text(SUMMARY)

    # Keep the original required substring checks.
    expected_lines = [
        "Host: [REDACTED]",
        "Client IP: [REDACTED]",
        "Timeout reaching [REDACTED]",
    ]
    for line in expected_lines:
        assert line in content, f"Expected redacted line '{line}' not found in summary.log."

    found_ips = IPV4_PATTERN.findall(content)
    assert not found_ips, f"Found unredacted IPv4 addresses in summary.log: {found_ips}"
    assert "[ERROR]" in content, "No [ERROR] blocks found in summary.log."

    records = parse_summary(content)
    assert Counter(records) == Counter(EXPECTED_ORIGINAL_RECORDS), (
        "summary.log does not contain exactly the complete redacted error records"
    )


def test_go_program_on_derived_inputs():
    nonce = secrets.token_hex(12)
    ip1 = f"10.{secrets.randbelow(200) + 1}.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}"
    ip2 = f"172.{secrets.randbelow(15) + 16}.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}"
    ip3 = f"192.168.{secrets.randbelow(250) + 1}.{secrets.randbelow(250) + 1}"

    record1 = f"[ERROR] dynamic-{nonce}\nFirst detail is preserved\nHost pair: {ip1} and {ip2}\n[INFO] still part of this record"
    record2 = f"[ERROR] second-{nonce}\nNo address on this line"
    record3 = f"[ERROR] nested-{nonce}\nClient: {ip3}\nFinal nested detail"
    record4 = f"[ERROR] eof-{nonce}\nAddress repeated: {ip1}"

    expected = [
        IPV4_PATTERN.sub("[REDACTED]", record1),
        IPV4_PATTERN.sub("[REDACTED]", record2),
        IPV4_PATTERN.sub("[REDACTED]", record3),
        IPV4_PATTERN.sub("[REDACTED]", record4),
    ]

    temp_root = tempfile.mkdtemp(prefix="verifier-process-logs-")
    saved_extracted = os.path.join(temp_root, "original-extracted")
    saved_summary = os.path.join(temp_root, "original-summary.log")

    shutil.move(EXTRACTED, saved_extracted)
    if os.path.exists(SUMMARY):
        shutil.move(SUMMARY, saved_summary)

    try:
        os.makedirs(os.path.join(EXTRACTED, "deep", "nested"))
        with open(os.path.join(EXTRACTED, f"first-{nonce}.log"), "w", encoding="utf-8") as f:
            f.write(
                f"[INFO] preface\n"
                f"prefix [ERROR] must not start a record\n"
                f"[ERRORISH] also not a record\n\n"
                f"{record1}\n\n"
                f"[DEBUG] between records\n"
                f"{record2}\n\n"
                f"[INFO] finished\n"
            )
        with open(os.path.join(EXTRACTED, "deep", "nested", f"other-{nonce}.log"), "w", encoding="utf-8") as f:
            f.write(f"noise\n\n{record3}\n\nmore noise\n{record4}")
        with open(os.path.join(EXTRACTED, f"ignored-{nonce}.txt"), "w", encoding="utf-8") as f:
            f.write(f"[ERROR] must-not-appear-{nonce}\nHost: {ip2}\n")

        result = subprocess.run(
            ["go", "run", SOURCE],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f"Go program failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(SUMMARY), "Running the Go program did not create summary.log"

        content = read_text(SUMMARY)
        assert not IPV4_PATTERN.findall(content), "Go program left IPv4 addresses unredacted"
        assert f"must-not-appear-{nonce}" not in content, "Program processed a non-.log file"
        records = parse_summary(content)
        assert Counter(records) == Counter(expected), (
            "Go program did not preserve and redact exactly the complete dynamic error records"
        )
    finally:
        if os.path.isdir(EXTRACTED):
            shutil.rmtree(EXTRACTED)
        if os.path.exists(SUMMARY):
            os.remove(SUMMARY)
        shutil.move(saved_extracted, EXTRACTED)
        if os.path.exists(saved_summary):
            shutil.move(saved_summary, SUMMARY)
        shutil.rmtree(temp_root, ignore_errors=True)
TEST_EOF

status=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
