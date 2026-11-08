#!/bin/bash

mkdir -p /logs/verifier || exit 1
echo "0" > /logs/verifier/reward.txt

# Restore the documented fixture so the original exact-content assertions test
# output freshly produced by the submitted script.
if ! cat << 'DATA_EOF' > /home/user/backup_logs.jsonl
{"job_id": "job_a1", "cluster": "alpha-cluster", "status": "FAILED", "duration_seconds": 100, "timestamp": "2023-10-01T10:00:00Z"}
{"job_id": "job_a2", "cluster": "alpha-cluster", "status": "FAILED", "duration_seconds": 200, "timestamp": "2023-10-01T11:00:00Z"}
{"job_id": "job_a3", "cluster": "alpha-cluster", "status": "FAILED", "duration_seconds": 150, "timestamp": "2023-10-01T12:00:00Z"}
{"job_id": "job_a4", "cluster": "alpha-cluster", "status": "FAILED", "duration_seconds": 50, "timestamp": "2023-10-01T13:00:00Z"}
{"job_id": "job_a5", "cluster": "alpha-cluster", "status": "SUCCESS", "duration_seconds": 500, "timestamp": "2023-10-01T14:00:00Z"}
{"job_id": "job_b1", "cluster": "beta-cluster", "status": "FAILED", "duration_seconds": 300, "timestamp": "2023-10-01T10:00:00Z"}
{"job_id": "job_b2", "cluster": "beta-cluster", "status": "FAILED", "duration_seconds": 300, "timestamp": "2023-10-01T11:00:00Z"}
{"job_id": "job_c1", "cluster": "gamma-cluster", "status": "SUCCESS", "duration_seconds": 120, "timestamp": "2023-10-01T10:00:00Z"}
{"job_id": "job_d1", "cluster": "delta-cluster", "status": "FAILED", "duration_seconds": 45, "timestamp": "2023-10-01T10:00:00Z"}
DATA_EOF
then
    exit 0
fi

if [ ! -f /home/user/process_backups.py ]; then
    exit 0
fi

rm -f /home/user/failed_backups_report.csv
if ! timeout 20s python3 /home/user/process_backups.py; then
    exit 0
fi

if ! cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

SCRIPT = "/home/user/process_backups.py"
INPUT = "/home/user/backup_logs.jsonl"
OUTPUT = "/home/user/failed_backups_report.csv"
HEADER = ["cluster", "avg_failed_duration", "longest_job_1", "longest_job_2", "longest_job_3"]


def test_script_file_exists():
    assert os.path.exists(SCRIPT), f"Expected Python script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"Path {SCRIPT} is not a file."


def test_csv_file_exists():
    """Verify that the output CSV file exists."""
    csv_file = "/home/user/failed_backups_report.csv"
    assert os.path.exists(csv_file), f"Expected output file {csv_file} does not exist. Did you create it?"
    assert os.path.isfile(csv_file), f"Path {csv_file} is not a file."


def test_csv_file_content():
    """Verify that the CSV file contains the correct aggregated and sorted data."""
    csv_file = "/home/user/failed_backups_report.csv"

    expected_rows = [
        ["cluster", "avg_failed_duration", "longest_job_1", "longest_job_2", "longest_job_3"],
        ["alpha-cluster", "125.0", "job_a2", "job_a3", "job_a1"],
        ["beta-cluster", "300.0", "job_b1", "job_b2", ""],
        ["delta-cluster", "45.0", "job_d1", "", ""]
    ]

    actual_rows = []
    with open(csv_file, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) > 0, f"The file {csv_file} is empty."
    assert actual_rows[0] == expected_rows[0], f"CSV header is incorrect. Expected {expected_rows[0]}, got {actual_rows[0]}."
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), but found {len(actual_rows)}."
    for i in range(1, len(expected_rows)):
        assert actual_rows[i] == expected_rows[i], f"Row {i+1} is incorrect. Expected {expected_rows[i]}, got {actual_rows[i]}."


def derive_expected(documents):
    groups = {}
    for document in documents:
        if document["status"] == "FAILED":
            groups.setdefault(document["cluster"], []).append(document)

    rows = [HEADER]
    for cluster in sorted(groups):
        jobs = groups[cluster]
        average = sum(job["duration_seconds"] for job in jobs) / len(jobs)
        ordered = sorted(jobs, key=lambda job: (-job["duration_seconds"], job["job_id"]))[:3]
        ids = [job["job_id"] for job in ordered]
        ids.extend([""] * (3 - len(ids)))
        rows.append([cluster, f"{average:.1f}", *ids])
    return rows


def test_script_processes_unseen_jsonl_data():
    token = secrets.token_hex(8)
    clusters = {
        "many": f"zeta-{token}",
        "single": f"alpha-{token}",
        "pair": f"middle-{token}",
        "none": f"empty-{token}",
    }
    documents = [
        {"job_id": f"b-{token}", "cluster": clusters["many"], "status": "FAILED", "duration_seconds": 400, "timestamp": "2026-01-01T00:00:00Z"},
        {"job_id": f"a-{token}", "cluster": clusters["many"], "status": "FAILED", "duration_seconds": 400, "timestamp": "2026-01-01T00:01:00Z"},
        {"job_id": f"c-{token}", "cluster": clusters["many"], "status": "FAILED", "duration_seconds": 120, "timestamp": "2026-01-01T00:02:00Z"},
        {"job_id": f"d-{token}", "cluster": clusters["many"], "status": "FAILED", "duration_seconds": 80, "timestamp": "2026-01-01T00:03:00Z"},
        {"job_id": f"ignored-{token}", "cluster": clusters["many"], "status": "SUCCESS", "duration_seconds": 9999, "timestamp": "2026-01-01T00:04:00Z"},
        {"job_id": f"case-{token}", "cluster": clusters["many"], "status": "failed", "duration_seconds": 8888, "timestamp": "2026-01-01T00:05:00Z"},
        {"job_id": f"one-{token}", "cluster": clusters["single"], "status": "FAILED", "duration_seconds": 17, "timestamp": "2026-01-01T00:06:00Z"},
        {"job_id": f"pair2-{token}", "cluster": clusters["pair"], "status": "FAILED", "duration_seconds": 20, "timestamp": "2026-01-01T00:07:00Z"},
        {"job_id": f"pair1-{token}", "cluster": clusters["pair"], "status": "FAILED", "duration_seconds": 10, "timestamp": "2026-01-01T00:08:00Z"},
        {"job_id": f"only-success-{token}", "cluster": clusters["none"], "status": "SUCCESS", "duration_seconds": 500, "timestamp": "2026-01-01T00:09:00Z"},
    ]

    with open(INPUT, "w", encoding="utf-8") as stream:
        for document in documents:
            stream.write(json.dumps(document) + "\n")

    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run(["python3", SCRIPT], cwd="/home/user", check=True, timeout=20)

    assert os.path.isfile(OUTPUT), "The script did not create the requested CSV output."
    with open(OUTPUT, "r", newline="", encoding="utf-8") as stream:
        actual_rows = list(csv.reader(stream))
    assert actual_rows == derive_expected(documents)
TEST_EOF
then
    exit 0
fi

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
