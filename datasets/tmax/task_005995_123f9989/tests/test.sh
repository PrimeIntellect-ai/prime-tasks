#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import secrets
import stat
import subprocess
import tempfile
import pytest

RAW_LOGS_PATH = "/home/user/raw_logs.txt"
CSV_PATH = "/home/user/import_ready.csv"
PIPELINE_LOG_PATH = "/home/user/pipeline.log"
C_SOURCE_PATH = "/home/user/process_logs.c"
C_BIN_PATH = "/home/user/process_logs"


def test_c_files_exist():
    assert os.path.exists(C_SOURCE_PATH), f"C source file missing: {C_SOURCE_PATH}"
    assert os.path.isfile(C_SOURCE_PATH), f"Not a file: {C_SOURCE_PATH}"

    assert os.path.exists(C_BIN_PATH), f"Compiled binary missing: {C_BIN_PATH}"
    assert os.path.isfile(C_BIN_PATH), f"Not a file: {C_BIN_PATH}"
    assert os.access(C_BIN_PATH, os.X_OK), f"Binary is not executable: {C_BIN_PATH}"


def test_csv_output():
    assert os.path.exists(CSV_PATH), f"CSV output file missing: {CSV_PATH}"
    assert os.path.isfile(CSV_PATH), f"Not a file: {CSV_PATH}"

    # Derive expected rows from the raw logs
    assert os.path.exists(RAW_LOGS_PATH), f"Raw logs missing, cannot verify: {RAW_LOGS_PATH}"

    expected_rows = []
    counts = {'2': 0, '4': 0, '5': 0}

    pattern = re.compile(r'^\[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\]$')

    with open(RAW_LOGS_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = pattern.match(line)
            if match:
                timestamp, ip, status, msg = match.groups()
                category = status[0]
                if category in counts and counts[category] < 5:
                    counts[category] += 1
                    expected_rows.append(f"{timestamp},{ip},{status},{msg}")

            if all(c == 5 for c in counts.values()):
                break

    expected_csv_content = ["timestamp,ip_address,status_code,message"] + expected_rows

    with open(CSV_PATH, "r") as f:
        actual_csv_content = [line.strip() for line in f if line.strip()]

    assert actual_csv_content == expected_csv_content, (
        f"CSV content in {CSV_PATH} does not match the expected stratified sample.\n"
        f"Expected {len(expected_csv_content)} rows, got {len(actual_csv_content)} rows."
    )


def test_pipeline_log_summary():
    assert os.path.exists(PIPELINE_LOG_PATH), f"Pipeline log missing: {PIPELINE_LOG_PATH}"
    assert os.path.isfile(PIPELINE_LOG_PATH), f"Not a file: {PIPELINE_LOG_PATH}"

    # We expect 5 of each based on the raw logs provided
    expected_log_entry = "[PROCESS_LOG] Stratification complete: 5 2xx, 5 4xx, 5 5xx extracted."

    with open(PIPELINE_LOG_PATH, "r") as f:
        log_content = f.read()

    assert expected_log_entry in log_content, (
        f"Expected summary log entry not found in {PIPELINE_LOG_PATH}.\n"
        f"Expected to find: '{expected_log_entry}'"
    )


def derive_expected(raw_text):
    expected_rows = []
    counts = {'2': 0, '4': 0, '5': 0}
    pattern = re.compile(r'^\[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\]$')
    for line in raw_text.splitlines():
        match = pattern.match(line.strip())
        if not match:
            continue
        timestamp, ip, status, msg = match.groups()
        category = status[0]
        if category in counts and counts[category] < 5:
            counts[category] += 1
            expected_rows.append(f"{timestamp},{ip},{status},{msg}")
        if all(c == 5 for c in counts.values()):
            break
    return ["timestamp,ip_address,status_code,message"] + expected_rows, counts


def make_unseen_input():
    nonce = secrets.token_hex(8)
    statuses = [200, 404, 500, 201, 403, 502, 302, 202, 400, 503,
                204, 401, 504, 205, 402, 505, 206, 405, 506]
    lines = []
    for i, status in enumerate(statuses, 1):
        lines.append(
            f"[2026-08-{(i % 27) + 1:02d} 17:{i:02d}:{(i * 3) % 60:02d}] "
            f"[172.20.{i // 250}.{(i % 250) + 1}] [{status}] "
            f"[Dynamic event {nonce} number {i}]"
        )
    return "\n".join(lines) + "\n"


def run_and_check(executable):
    paths = [RAW_LOGS_PATH, CSV_PATH, PIPELINE_LOG_PATH]
    snapshots = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                snapshots[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            snapshots[path] = None

    raw_text = make_unseen_input()
    expected_csv, counts = derive_expected(raw_text)
    expected_summary = (
        f"[PROCESS_LOG] Stratification complete: {counts['2']} 2xx, "
        f"{counts['4']} 4xx, {counts['5']} 5xx extracted."
    )

    try:
        with open(RAW_LOGS_PATH, "w") as f:
            f.write(raw_text)
        for path in (CSV_PATH, PIPELINE_LOG_PATH):
            if os.path.lexists(path):
                os.remove(path)

        result = subprocess.run(
            [executable], cwd="/home/user", capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            f"{executable} failed with exit code {result.returncode}.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(CSV_PATH), "Program did not create import_ready.csv"
        with open(CSV_PATH, "r") as f:
            actual_csv = [line.strip() for line in f if line.strip()]
        assert actual_csv == expected_csv, "Program failed on an unseen raw log input"

        assert os.path.isfile(PIPELINE_LOG_PATH), "Program did not create pipeline.log"
        with open(PIPELINE_LOG_PATH, "r") as f:
            log_content = f.read()
        assert expected_summary in log_content, (
            f"Expected dynamically derived summary not found: {expected_summary}"
        )
    finally:
        for path, snapshot in snapshots.items():
            if snapshot is None:
                if os.path.lexists(path):
                    os.remove(path)
            else:
                data, mode = snapshot
                with open(path, "wb") as f:
                    f.write(data)
                os.chmod(path, mode)


def test_installed_program_on_unseen_input():
    with open(C_BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "process_logs is not a compiled native executable"
    run_and_check(C_BIN_PATH)


def test_c_source_compiles_and_works_on_unseen_input():
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "process_logs_rebuilt")
        result = subprocess.run(
            ["gcc", "-std=c11", "-O2", C_SOURCE_PATH, "-o", rebuilt],
            capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, (
            f"C source did not compile.\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        run_and_check(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
