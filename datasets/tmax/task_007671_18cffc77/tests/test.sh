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

REPO = "/home/user/log_processor"
PROCESS_SCRIPT = os.path.join(REPO, "process.py")
SOURCE_CSV = os.path.join(REPO, "server_logs.csv")
OUTPUT_CSV = "/home/user/processed_logs.csv"
SECRET = "xtk_99281_devops_secret"


def run_processor():
    env = os.environ.copy()
    env["SECRET_TOKEN"] = SECRET
    try:
        result = subprocess.run(
            ["python3", PROCESS_SCRIPT],
            cwd=REPO,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("process.py still hangs instead of completing")
    assert result.returncode == 0, (
        f"process.py exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_CSV), "process.py did not create processed_logs.csv"


def test_process_script_executes_and_filters_runtime_input():
    assert os.path.isfile(PROCESS_SCRIPT), f"Missing executable artifact {PROCESS_SCRIPT}"
    assert os.path.isfile(SOURCE_CSV), f"Missing input file {SOURCE_CSV}"

    with open(SOURCE_CSV, "rb") as f:
        original_csv = f.read()

    nonce = secrets.token_hex(12)
    rows = [
        [f"{nonce}-01", "INFO", "web", f"ignore-{nonce}-1"],
        [f"{nonce}-02", "CRITICAL", "auth", f"keep-{nonce}-1"],
        [f"{nonce}-03", "CRITICAL", "web", f"ignore-{nonce}-2"],
        [f"{nonce}-04", "ERROR", "auth", f"ignore-{nonce}-3"],
        [f"{nonce}-05", "CRITICAL", "auth", f"keep-{nonce}-2"],
        [f"{nonce}-06", "critical", "auth", f"ignore-{nonce}-4"],
    ]
    expected = [dict(zip(["timestamp", "level", "service", "message"], rows[1])),
                dict(zip(["timestamp", "level", "service", "message"], rows[4]))]

    try:
        with open(SOURCE_CSV, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "level", "service", "message"])
            writer.writerows(rows)
        if os.path.exists(OUTPUT_CSV):
            os.remove(OUTPUT_CSV)

        run_processor()

        with open(OUTPUT_CSV, newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == ["timestamp", "level", "service", "message"]
            actual = list(reader)
        assert actual == expected, (
            "process.py did not select exactly the runtime rows where "
            "level is CRITICAL and service is auth"
        )
    finally:
        with open(SOURCE_CSV, "wb") as f:
            f.write(original_csv)

    if os.path.exists(OUTPUT_CSV):
        os.remove(OUTPUT_CSV)
    run_processor()


def test_debug_report_exists_and_valid():
    report_path = "/home/user/debug_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist"

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON")

    assert "recovered_secret" in report, "Missing 'recovered_secret' in report"
    assert report["recovered_secret"] == "xtk_99281_devops_secret", "Incorrect 'recovered_secret'"

    assert "blocking_file" in report, "Missing 'blocking_file' in report"
    assert report["blocking_file"] == "/tmp/config_pipe", "Incorrect 'blocking_file'"

    assert "critical_auth_count" in report, "Missing 'critical_auth_count' in report"
    assert report["critical_auth_count"] == 2, "Incorrect 'critical_auth_count'"


def test_processed_logs_csv():
    csv_path = "/home/user/processed_logs.csv"
    assert os.path.isfile(csv_path), f"Processed logs file {csv_path} does not exist"

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines (1 header + 2 rows) in {csv_path}, but got {len(lines)}"

    expected_header = "timestamp,level,service,message"
    assert lines[0] == expected_header, f"Expected header '{expected_header}', got '{lines[0]}'"

    expected_rows = [
        "2023-10-01T10:01:00,CRITICAL,auth,Authentication bypassed",
        "2023-10-01T10:03:00,CRITICAL,auth,Multiple failed logins"
    ]

    for row in expected_rows:
        assert row in lines, f"Expected row '{row}' not found in {csv_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
