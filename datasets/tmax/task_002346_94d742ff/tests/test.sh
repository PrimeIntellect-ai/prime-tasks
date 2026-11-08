#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import secrets
import shutil
import subprocess
import sys
import tempfile

import pytest

WORKSPACE_DIR = "/home/user/ticket_8492"
LOGS_DIR = os.path.join(WORKSPACE_DIR, "logs")
ENV_FILE = os.path.join(WORKSPACE_DIR, ".env")
SCRIPT_FILE = os.path.join(WORKSPACE_DIR, "aggregate_logs.py")
REPORT_FILE = os.path.join(WORKSPACE_DIR, "report.json")
RESOLUTION_FILE = os.path.join(WORKSPACE_DIR, "resolution.txt")


def read_expected(log_dir):
    files = sorted(
        os.path.join(log_dir, name)
        for name in os.listdir(log_dir)
        if name.endswith(".txt")
    )
    count = 0
    total = 0.0
    negatives = []
    for path in files:
        with open(path, "r") as f:
            for raw_line in f:
                line = raw_line.strip()
                parts = line.split(",")
                if len(parts) == 2:
                    value = float(parts[1])
                    count += 1
                    total += value
                    if value < 0:
                        negatives.append((os.path.basename(path), line))
    average = round(total / count, 2) if count else 0
    return count, average, len(files), negatives


def run_script():
    if os.path.exists(REPORT_FILE):
        os.remove(REPORT_FILE)
    result = subprocess.run(
        [sys.executable, SCRIPT_FILE],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"aggregate_logs.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_FILE), "Running aggregate_logs.py did not generate report.json."
    with open(REPORT_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Generated report.json is not valid JSON: {exc}")


def assert_report(report, expected_requests, expected_average, expected_files):
    assert "total_requests" in report, "Report JSON missing 'total_requests' key."
    assert report["total_requests"] == expected_requests, (
        f"Expected total_requests to be {expected_requests}, got {report['total_requests']}. "
        "The race condition might not be fully fixed."
    )
    assert "files_processed" in report, "Report JSON missing 'files_processed' key."
    assert report["files_processed"] == expected_files, (
        f"Expected files_processed to be {expected_files}, got {report['files_processed']}."
    )
    assert "average_response_time" in report, "Report JSON missing 'average_response_time' key."
    assert isinstance(report["average_response_time"], (int, float)) and not isinstance(
        report["average_response_time"], bool
    ), "average_response_time must be numeric."
    assert math.isclose(report["average_response_time"], expected_average, abs_tol=1e-9), (
        f"Expected average_response_time to be {expected_average}, "
        f"got {report['average_response_time']}."
    )


def test_resolution_file_exists_and_correct():
    assert os.path.isfile(RESOLUTION_FILE), f"Resolution file {RESOLUTION_FILE} is missing."
    with open(RESOLUTION_FILE, "r") as f:
        raw_lines = f.read().splitlines()

    assert len(raw_lines) == 2, f"Resolution file must contain exactly two lines, found {len(raw_lines)}."
    lines = [line.strip() for line in raw_lines]

    _, _, _, negatives = read_expected(LOGS_DIR)
    assert len(negatives) == 1, f"Expected exactly one negative response-time line, found {len(negatives)}."
    expected_filename, expected_line = negatives[0]
    assert lines[0] == expected_filename, (
        f"First line of resolution.txt should be {expected_filename!r}, got: {lines[0]!r}"
    )
    assert lines[1] == expected_line, (
        f"Second line of resolution.txt should be exactly {expected_line!r}, got: {lines[1]!r}"
    )

    # Preserve the original concrete assertions for this ticket's supplied data.
    assert "log_027.txt" in lines[0], (
        f"First line of resolution.txt should contain 'log_027.txt', got: {lines[0]}"
    )
    assert lines[1] == "REQ_027_ANOMALY,-99999.999", (
        "Second line of resolution.txt should be exactly "
        f"'REQ_027_ANOMALY,-99999.999', got: {lines[1]}"
    )


def test_env_file_fixed():
    assert os.path.isfile(ENV_FILE), f".env file {ENV_FILE} is missing."
    with open(ENV_FILE, "r") as f:
        content = f.read().strip()

    assert "LOG_DIR=" in content, ".env file must contain LOG_DIR assignment."
    val = content.split("LOG_DIR=")[1].strip()
    valid_paths = [LOGS_DIR, "./logs", "logs"]
    assert val in valid_paths, (
        f".env file LOG_DIR is set to '{val}', expected one of {valid_paths}."
    )


def test_script_modified_for_concurrency():
    assert os.path.isfile(SCRIPT_FILE), f"Script file {SCRIPT_FILE} is missing."
    with open(SCRIPT_FILE, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert (
        "Intentional race condition here" not in content
        or "Lock" in content
        or "total_requests" in content
    ), "The script does not seem to be properly modified to handle the race condition."

    try:
        tree = ast.parse(content, filename=SCRIPT_FILE)
    except SyntaxError as exc:
        pytest.fail(f"aggregate_logs.py is not valid Python: {exc}")

    thread_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in {"ThreadPoolExecutor", "Thread"}:
            thread_calls.append(node)
        elif isinstance(node.func, ast.Attribute) and node.func.attr in {"ThreadPoolExecutor", "Thread"}:
            thread_calls.append(node)

    assert thread_calls, "aggregate_logs.py must still use multiple threads to process files concurrently."
    for call in thread_calls:
        name = call.func.id if isinstance(call.func, ast.Name) else call.func.attr
        if name == "ThreadPoolExecutor":
            for keyword in call.keywords:
                if keyword.arg == "max_workers" and isinstance(keyword.value, ast.Constant):
                    assert keyword.value.value is None or keyword.value.value > 1, (
                        "ThreadPoolExecutor must be configured to permit multiple worker threads."
                    )


def test_script_on_unpredictable_concurrent_workload():
    original_env = open(ENV_FILE, "rb").read() if os.path.exists(ENV_FILE) else None
    original_report = open(REPORT_FILE, "rb").read() if os.path.exists(REPORT_FILE) else None
    fixture_dir = tempfile.mkdtemp(prefix="ticket8492_logs_")

    try:
        rng = secrets.SystemRandom()
        file_count = rng.randint(70, 95)
        expected_requests = 0
        expected_total = 0.0

        for index in range(file_count):
            line_count = rng.randint(5, 18)
            path = os.path.join(fixture_dir, f"input_{index:04d}_{rng.randrange(1 << 30):x}.txt")
            with open(path, "w") as f:
                for line_index in range(line_count):
                    # Integral float values make the correctly rounded average deterministic.
                    value = float(rng.randint(1, 500))
                    f.write(f"DYNAMIC_{index}_{line_index},{value:.1f}\n")
                    expected_requests += 1
                    expected_total += value

        expected_average = round(expected_total / expected_requests, 2)
        with open(ENV_FILE, "w") as f:
            f.write(f"LOG_DIR={fixture_dir}\n")

        # Repeated execution catches the original read/sleep/write race and proves
        # that report.json is produced by the submitted script rather than prewritten.
        for _ in range(3):
            report = run_script()
            assert_report(report, expected_requests, expected_average, file_count)
    finally:
        shutil.rmtree(fixture_dir, ignore_errors=True)
        if original_env is None:
            if os.path.exists(ENV_FILE):
                os.remove(ENV_FILE)
        else:
            with open(ENV_FILE, "wb") as f:
                f.write(original_env)
        if original_report is None:
            if os.path.exists(REPORT_FILE):
                os.remove(REPORT_FILE)
        else:
            with open(REPORT_FILE, "wb") as f:
                f.write(original_report)


def test_report_json_correct_after_actual_execution():
    expected_requests, expected_average, expected_files, _ = read_expected(LOGS_DIR)
    report = run_script()
    assert_report(report, expected_requests, expected_average, expected_files)

    # Preserve the original concrete assertions for the supplied ticket data.
    assert report["total_requests"] == 5001, (
        f"Expected total_requests to be 5001, got {report['total_requests']}. "
        "The race condition might not be fully fixed."
    )
    assert report["files_processed"] == 50, (
        f"Expected files_processed to be 50, got {report['files_processed']}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
