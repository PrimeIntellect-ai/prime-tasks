#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
from collections import defaultdict

import pytest

LOG_FILE = "/home/user/data/sensor_raw.log"
SOURCE_FILE = "/home/user/etl_processor.c"
WRAPPER = "/home/user/run_pipeline.sh"
COMPILED_TEST_BINARY = "/tmp/etl_processor_verifier"
PIPELINE_BINARY = "/home/user/etl_processor"
OUTPUT_DIR = "/home/user/output"
AGG_CSV = "/home/user/output/aggregated.csv"
ETL_LOG = "/home/user/output/etl.log"
GATE_PASSED = "/home/user/output/quality_gate_passed"
GATE_FAILED = "/home/user/output/quality_gate_failed"


def get_expected_data(path):
    total = 0
    valid = 0
    invalid = 0
    agg = defaultdict(lambda: {'temps': [], 'hums': []})

    if not os.path.exists(path):
        return 0, 0, 0, []

    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            total += 1
            m = re.match(r'\[(.*?)\] SENSOR_LOG device=(\S+) temp=([0-9.-]+) hum=([0-9.-]+)', line)
            if not m:
                invalid += 1
                continue

            ts, device, temp_str, hum_str = m.groups()
            try:
                temp = float(temp_str)
                hum = float(hum_str)
            except ValueError:
                invalid += 1
                continue

            if -50.0 <= temp <= 150.0 and 0.0 <= hum <= 100.0:
                valid += 1
                bucket = ts[:14] + "00:00Z"
                agg[(bucket, device)]['temps'].append(temp)
                agg[(bucket, device)]['hums'].append(hum)
            else:
                invalid += 1

    csv_lines = []
    for (bucket, device) in sorted(agg.keys()):
        temps = agg[(bucket, device)]['temps']
        hums = agg[(bucket, device)]['hums']
        avg_temp = sum(temps) / len(temps)
        avg_hum = sum(hums) / len(hums)
        csv_lines.append(f"{bucket},{device},{avg_temp:.2f},{avg_hum:.2f}")

    return total, valid, invalid, csv_lines


def clean_output():
    shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)


def assert_aggregated_csv(input_path):
    assert os.path.exists(AGG_CSV), f"Output file {AGG_CSV} does not exist."
    _, _, _, expected_csv_lines = get_expected_data(input_path)
    with open(AGG_CSV, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_csv_lines, (
        f"Contents of {AGG_CSV} do not match expected.\n"
        f"Expected:\n{chr(10).join(expected_csv_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def assert_etl_log(input_path):
    assert os.path.exists(ETL_LOG), f"Log file {ETL_LOG} does not exist."
    total, valid, invalid, _ = get_expected_data(input_path)
    expected_log_line = f"TOTAL:{total} VALID:{valid} INVALID:{invalid}"
    with open(ETL_LOG, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert len(actual_lines) == 1, f"{ETL_LOG} should contain exactly one line, found {len(actual_lines)}."
    assert actual_lines[0] == expected_log_line, (
        f"ETL log line mismatch.\nExpected: {expected_log_line}\nActual: {actual_lines[0]}"
    )


def assert_quality_gate(input_path):
    total, _, invalid, _ = get_expected_data(input_path)
    if total == 0:
        pytest.skip("No data to test quality gate.")
    ratio = invalid / total
    if ratio > 0.10:
        assert os.path.exists(GATE_FAILED), f"Expected {GATE_FAILED} to exist because invalid ratio is {ratio:.2f} (> 0.10)."
        assert not os.path.exists(GATE_PASSED), f"Expected {GATE_PASSED} to NOT exist because invalid ratio is {ratio:.2f} (> 0.10)."
    else:
        assert os.path.exists(GATE_PASSED), f"Expected {GATE_PASSED} to exist because invalid ratio is {ratio:.2f} (<= 0.10)."
        assert not os.path.exists(GATE_FAILED), f"Expected {GATE_FAILED} to NOT exist because invalid ratio is {ratio:.2f} (<= 0.10)."


def run_checked(command):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    assert result.returncode == 0, f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}"


def test_program_and_pipeline_behavior():
    assert os.path.lexists(SOURCE_FILE), f"Required source file {SOURCE_FILE} does not exist."
    assert stat.S_ISREG(os.lstat(SOURCE_FILE).st_mode), f"{SOURCE_FILE} must be a regular file."
    assert os.path.lexists(WRAPPER), f"Required wrapper {WRAPPER} does not exist."
    wrapper_mode = os.lstat(WRAPPER).st_mode
    assert stat.S_ISREG(wrapper_mode), f"{WRAPPER} must be a regular file."
    assert wrapper_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), f"{WRAPPER} is not executable."
    assert os.path.exists(LOG_FILE), f"Input file {LOG_FILE} does not exist."

    with open(LOG_FILE, 'rb') as f:
        original_input = f.read()

    token = secrets.token_hex(4).upper()
    direct_input = f"/tmp/direct_sensor_{token}.log"
    direct_data = "\n".join([
        f"[2025-02-14T06:05:00Z] SENSOR_LOG device=DX{token} temp=-50.0 hum=0.0",
        f"[2025-02-14T06:45:00Z] SENSOR_LOG device=DX{token} temp=150.0 hum=100.0",
        f"[2025-02-14T07:15:00Z] SENSOR_LOG device=DY{token} temp=31.0 hum=61.0",
        f"[2025-02-14T07:20:00Z] SENSOR_LOG device=DY{token} temp=151.0 hum=50.0",
        f"[2025-02-14T07:25:00Z] SENSOR_LOG device=DZ{token} temp=20.0 hum=-1.0",
    ]) + "\n"

    wrapper_data = "\n".join([
        f"[2024-03-09T07:01:00Z] SENSOR_LOG device=A{token} temp=-50.0 hum=0.0",
        f"[2024-03-09T07:31:00Z] SENSOR_LOG device=A{token} temp=150.0 hum=100.0",
        f"[2024-03-09T08:01:00Z] SENSOR_LOG device=B{token} temp=11.0 hum=41.0",
        f"[2024-03-09T08:11:00Z] SENSOR_LOG device=B{token} temp=21.0 hum=51.0",
        f"[2024-03-09T08:21:00Z] SENSOR_LOG device=B{token} temp=31.0 hum=61.0",
        f"[2024-03-10T01:05:00Z] SENSOR_LOG device=C{token} temp=5.0 hum=15.0",
        f"[2024-03-10T01:15:00Z] SENSOR_LOG device=C{token} temp=15.0 hum=25.0",
        f"[2024-03-10T02:05:00Z] SENSOR_LOG device=A{token} temp=45.0 hum=75.0",
        f"[2024-03-10T02:55:00Z] SENSOR_LOG device=A{token} temp=55.0 hum=85.0",
        f"[2024-03-10T03:00:00Z] SENSOR_LOG device=C{token} temp=10.0 hum=100.1",
    ]) + "\n"

    try:
        run_checked(["gcc", "-O2", SOURCE_FILE, "-o", COMPILED_TEST_BINARY])
        assert os.path.isfile(COMPILED_TEST_BINARY) and os.access(COMPILED_TEST_BINARY, os.X_OK)

        with open(direct_input, 'w') as f:
            f.write(direct_data)
        clean_output()
        run_checked([COMPILED_TEST_BINARY, direct_input])
        assert_aggregated_csv(direct_input)
        assert_etl_log(direct_input)

        with open(LOG_FILE, 'w') as f:
            f.write(wrapper_data)
        clean_output()
        if os.path.lexists(PIPELINE_BINARY):
            os.remove(PIPELINE_BINARY)
        run_checked([WRAPPER])
        assert os.path.isfile(PIPELINE_BINARY), "The wrapper did not create /home/user/etl_processor."
        assert os.access(PIPELINE_BINARY, os.X_OK), "The wrapper's compiled program is not executable."
        assert_aggregated_csv(LOG_FILE)
        assert_etl_log(LOG_FILE)
        assert_quality_gate(LOG_FILE)

        with open(LOG_FILE, 'wb') as f:
            f.write(original_input)
        clean_output()
        run_checked([WRAPPER])
        assert_aggregated_csv(LOG_FILE)
        assert_etl_log(LOG_FILE)
        assert_quality_gate(LOG_FILE)
    finally:
        with open(LOG_FILE, 'wb') as f:
            f.write(original_input)
        if os.path.exists(direct_input):
            os.remove(direct_input)
        if os.path.exists(COMPILED_TEST_BINARY):
            os.remove(COMPILED_TEST_BINARY)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
