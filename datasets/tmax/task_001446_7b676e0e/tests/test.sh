#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import secrets
import subprocess
from pathlib import Path
from collections import defaultdict

SCRIPT_PATH = Path("/home/user/analyze_retries.py")
LOGS_PATH = Path("/home/user/data/pipeline_logs.jsonl")
CSV_PATH = Path("/home/user/data/output_data.csv")
REPORT_PATH = Path("/home/user/anomaly_report.json")


def compute_truth():
    logs_path = "/home/user/data/pipeline_logs.jsonl"
    csv_path = "/home/user/data/output_data.csv"

    retried_jobs = set()
    if os.path.exists(logs_path):
        with open(logs_path, 'r') as f:
            for line in f:
                if not line.strip():
                    continue
                record = json.loads(line)
                if record.get("status") == "RETRYING":
                    retried_jobs.add(record.get("job_id"))

    retried_jobs_sorted = sorted(list(retried_jobs))

    duplicates_per_job = defaultdict(int)
    record_counts = defaultdict(lambda: defaultdict(int))

    if os.path.exists(csv_path):
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                job_id = row.get("job_id")
                record_id = row.get("record_id")
                if job_id in retried_jobs:
                    record_counts[job_id][record_id] += 1

    for job_id, records in record_counts.items():
        for rec_id, count in records.items():
            if count > 1:
                duplicates_per_job[job_id] += (count - 1)

    total_duplicates = sum(duplicates_per_job.values())
    max_job = max(duplicates_per_job.keys(), key=lambda j: duplicates_per_job[j]) if duplicates_per_job else None

    return {
        "retried_jobs": retried_jobs_sorted,
        "total_duplicates_from_retries": total_duplicates,
        "max_retry_spike_job": max_job
    }


def assert_report_matches(expected):
    assert REPORT_PATH.is_file(), f"The anomaly report file {REPORT_PATH} does not exist."
    try:
        with REPORT_PATH.open('r') as f:
            student_report = json.load(f)
    except json.JSONDecodeError:
        assert False, f"The file {REPORT_PATH} does not contain valid JSON."

    assert "retried_jobs" in student_report, "Missing 'retried_jobs' key in the report."
    assert student_report["retried_jobs"] == expected["retried_jobs"], \
        f"Expected retried_jobs to be {expected['retried_jobs']}, but got {student_report['retried_jobs']}"

    assert "total_duplicates_from_retries" in student_report, "Missing 'total_duplicates_from_retries' key in the report."
    assert student_report["total_duplicates_from_retries"] == expected["total_duplicates_from_retries"], \
        f"Expected total_duplicates_from_retries to be {expected['total_duplicates_from_retries']}, but got {student_report['total_duplicates_from_retries']}"

    assert "max_retry_spike_job" in student_report, "Missing 'max_retry_spike_job' key in the report."
    assert student_report["max_retry_spike_job"] == expected["max_retry_spike_job"], \
        f"Expected max_retry_spike_job to be {expected['max_retry_spike_job']}, but got {student_report['max_retry_spike_job']}"


def test_anomaly_report_exists():
    report_path = "/home/user/anomaly_report.json"
    assert os.path.isfile(report_path), f"The anomaly report file {report_path} does not exist."


def test_anomaly_report_content():
    report_path = "/home/user/anomaly_report.json"
    assert os.path.isfile(report_path), f"The anomaly report file {report_path} does not exist."

    with open(report_path, 'r') as f:
        try:
            student_report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {report_path} does not contain valid JSON."

    expected_truth = compute_truth()

    assert "retried_jobs" in student_report, "Missing 'retried_jobs' key in the report."
    assert student_report["retried_jobs"] == expected_truth["retried_jobs"], \
        f"Expected retried_jobs to be {expected_truth['retried_jobs']}, but got {student_report['retried_jobs']}"

    assert "total_duplicates_from_retries" in student_report, "Missing 'total_duplicates_from_retries' key in the report."
    assert student_report["total_duplicates_from_retries"] == expected_truth["total_duplicates_from_retries"], \
        f"Expected total_duplicates_from_retries to be {expected_truth['total_duplicates_from_retries']}, but got {student_report['total_duplicates_from_retries']}"

    assert "max_retry_spike_job" in student_report, "Missing 'max_retry_spike_job' key in the report."
    assert student_report["max_retry_spike_job"] == expected_truth["max_retry_spike_job"], \
        f"Expected max_retry_spike_job to be {expected_truth['max_retry_spike_job']}, but got {student_report['max_retry_spike_job']}"


def write_dynamic_fixture(case_number):
    token = secrets.token_hex(8)
    jobs = [f"{token}_zeta", f"{token}_alpha", f"{token}_middle"]
    non_retry_job = f"{token}_ordinary"

    offset = secrets.randbelow(4)
    if case_number == 1:
        duplicate_counts = [offset + 2, offset + 8, offset + 4]
    else:
        duplicate_counts = [offset + 9, offset + 3, offset + 5]

    with LOGS_PATH.open('w') as f:
        for index, job in enumerate(jobs):
            for status in ("STARTED", "FAILED", "RETRYING", "SUCCESS"):
                record = {
                    "timestamp": f"2026-01-{index + 1:02d}T00:00:00",
                    "job_id": job,
                    "status": status,
                    "records_processed": index
                }
                f.write(json.dumps(record) + "\n")
        f.write(json.dumps({
            "timestamp": "2026-02-01T00:00:00",
            "job_id": non_retry_job,
            "status": "SUCCESS",
            "records_processed": 1
        }) + "\n")

    with CSV_PATH.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["record_id", "job_id", "data_payload"])
        for index, (job, duplicate_count) in enumerate(zip(jobs, duplicate_counts)):
            repeated_id = f"{token}_repeated_{index}"
            for occurrence in range(duplicate_count + 1):
                writer.writerow([repeated_id, job, f"payload_{occurrence}"])
            writer.writerow([f"{token}_unique_{index}", job, "unique"])

        # Duplicates from a job without RETRYING must not be counted.
        for occurrence in range(20):
            writer.writerow([f"{token}_ignored", non_retry_job, str(occurrence)])


def test_script_exists_and_recomputes_report_from_inputs():
    assert SCRIPT_PATH.is_file(), f"Required script {SCRIPT_PATH} does not exist or is not a regular file."
    assert not SCRIPT_PATH.is_symlink(), f"Required script {SCRIPT_PATH} must be an actual file, not a symbolic link."

    original_logs = LOGS_PATH.read_bytes()
    original_csv = CSV_PATH.read_bytes()
    original_report = REPORT_PATH.read_bytes() if REPORT_PATH.exists() else None

    try:
        for case_number in (1, 2):
            write_dynamic_fixture(case_number)
            expected = compute_truth()
            if REPORT_PATH.exists():
                REPORT_PATH.unlink()

            result = subprocess.run(
                ["python3", str(SCRIPT_PATH)],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=20
            )
            assert result.returncode == 0, \
                f"Executing {SCRIPT_PATH} failed with code {result.returncode}: {result.stderr}"
            assert_report_matches(expected)
    finally:
        LOGS_PATH.write_bytes(original_logs)
        CSV_PATH.write_bytes(original_csv)
        if original_report is None:
            if REPORT_PATH.exists():
                REPORT_PATH.unlink()
        else:
            REPORT_PATH.write_bytes(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
