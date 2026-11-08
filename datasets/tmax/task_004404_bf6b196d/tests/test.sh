#!/bin/bash
set +e
mkdir -p /logs/verifier

cp /home/user/telemetry.jsonl /tmp/original_telemetry.jsonl
if [ -e /home/user/anomaly_report.txt ]; then
    cp /home/user/anomaly_report.txt /tmp/original_anomaly_report.txt
    HAD_REPORT=1
else
    HAD_REPORT=0
fi

restore_files() {
    cp /tmp/original_telemetry.jsonl /home/user/telemetry.jsonl
    if [ "$HAD_REPORT" = "1" ]; then
        cp /tmp/original_anomaly_report.txt /home/user/anomaly_report.txt
    else
        rm -f /home/user/anomaly_report.txt
    fi
}
trap restore_files EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import random
import subprocess
import pytest

SOURCE = "/home/user/detect_anomaly.c"
EXECUTABLE = "/home/user/detect_anomaly"
TELEMETRY = "/home/user/telemetry.jsonl"
REPORT = "/home/user/anomaly_report.txt"


def compute_expected_anomaly():
    telemetry_path = "/home/user/telemetry.jsonl"
    if not os.path.exists(telemetry_path):
        return None, None

    bucket_counts = {}

    with open(telemetry_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            if '"status": "failed"' in line:
                continue
            if '"action": "edit"' in line:
                match = re.search(r'"timestamp"\s*:\s*(\d+)', line)
                if match:
                    ts = int(match.group(1))
                    bucket_id = ts // 3600
                    bucket_counts[bucket_id] = bucket_counts.get(bucket_id, 0) + 1

    sorted_buckets = sorted(bucket_counts.keys())

    sum_edits = 0
    count_buckets = 0

    for bucket in sorted_buckets:
        edits = bucket_counts[bucket]
        if count_buckets >= 5:
            mean = sum_edits / count_buckets
            if edits > 3.0 * mean:
                return bucket * 3600, edits

        sum_edits += edits
        count_buckets += 1

    return None, None


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    subprocess.run(
        ["gcc", SOURCE, "-o", EXECUTABLE],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    if os.path.exists(REPORT):
        os.remove(REPORT)
    subprocess.run([EXECUTABLE], check=True, timeout=30)


def test_c_source_exists():
    """Test that the C source code file exists."""
    c_file = "/home/user/detect_anomaly.c"
    assert os.path.exists(c_file), f"Missing C source file: {c_file}"


def test_anomaly_report_exists_and_correct():
    """Test that the anomaly_report.txt file exists and contains the correct output."""
    report_file = "/home/user/anomaly_report.txt"
    assert os.path.exists(report_file), f"Missing anomaly report file: {report_file}"

    expected_hour, expected_count = compute_expected_anomaly()
    assert expected_hour is not None, "Could not find an anomaly in the telemetry data."

    expected_text = f"ANOMALY_HOUR: {expected_hour}, COUNT: {expected_count}"

    with open(report_file, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert content == expected_text, f"Report content is incorrect. Expected '{expected_text}', got '{content}'"


def test_uses_posix_regex():
    with open(SOURCE, "r", encoding="utf-8", errors="ignore") as f:
        source = f.read()

    assert re.search(r"#\s*include\s*[<\"]regex\.h[>\"]", source), "Source must include regex.h"
    assert re.search(r"\bregcomp\s*\(", source), "Source must compile a POSIX regular expression with regcomp"
    assert re.search(r"\bregexec\s*\(", source), "Source must execute a POSIX regular expression with regexec"

    symbols = subprocess.run(
        ["nm", "-D", EXECUTABLE],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    ).stdout
    assert re.search(r"\bregcomp(?:@|\b)", symbols), "Compiled program does not reference POSIX regcomp"
    assert re.search(r"\bregexec(?:@|\b)", symbols), "Compiled program does not reference POSIX regexec"


def make_secret_case():
    base_bucket = 600000 + secrets.randbelow(100000)
    baseline = [4 + secrets.randbelow(5) for _ in range(6)]
    anomaly_count = int(3.0 * (sum(baseline) / len(baseline))) + 2
    counts = baseline + [anomaly_count, 5 + secrets.randbelow(4)]
    lines = []

    for offset, count in enumerate(counts):
        bucket = base_bucket + offset
        for _ in range(count):
            ts = bucket * 3600 + secrets.randbelow(3600)
            lines.append(f'{{"timestamp": {ts}, "action": "edit", "user": "secret", "status": "success", "text": "ok"}}\n')

        failed_ts = bucket * 3600 + secrets.randbelow(3600)
        lines.append(f'{{"timestamp": {failed_ts}, "action": "edit", "status": "failed", "text": "bad\\uG"}}\n')
        view_ts = bucket * 3600 + secrets.randbelow(3600)
        lines.append(f'{{"timestamp": {view_ts}, "action": "view", "status": "success"}}\n')

    random.SystemRandom().shuffle(lines)
    with open(TELEMETRY, "w", encoding="utf-8") as f:
        f.writelines(lines)


def test_executable_processes_unseen_telemetry():
    for _ in range(2):
        make_secret_case()
        expected_hour, expected_count = compute_expected_anomaly()
        assert expected_hour is not None
        expected = f"ANOMALY_HOUR: {expected_hour}, COUNT: {expected_count}"

        if os.path.exists(REPORT):
            os.remove(REPORT)
        subprocess.run([EXECUTABLE], check=True, timeout=30)

        assert os.path.exists(REPORT), "Program did not create anomaly_report.txt"
        with open(REPORT, "r", encoding="utf-8") as f:
            actual = f.read().strip()
        assert actual == expected, f"Program failed unseen telemetry case: expected '{expected}', got '{actual}'"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
restore_files
trap - EXIT

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
