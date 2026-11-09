#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import subprocess
import csv
import tempfile
import pytest
from datetime import datetime, timedelta

CLEANER_SCRIPT = "/home/user/cleaner.py"
EVIL_DIR = "/home/user/data/evil/"
CLEAN_DIR = "/home/user/data/clean/"
LOG_FILE = "/home/user/processing.log"
LEGACY_QC = "/app/legacy_qc"


def test_cleaner_script_exists():
    assert os.path.exists(CLEANER_SCRIPT), f"Cleaner script missing at {CLEANER_SCRIPT}"
    assert os.path.isfile(CLEANER_SCRIPT), f"{CLEANER_SCRIPT} is not a file"


def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.csv"))
    assert len(evil_files) > 0, "No evil files found to test."

    bypassed_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for evil_file in evil_files:
            out_file = os.path.join(tmpdir, "out.csv")
            if os.path.exists(out_file):
                os.remove(out_file)
            result = subprocess.run(
                ["python3", CLEANER_SCRIPT, evil_file, out_file],
                capture_output=True
            )
            if result.returncode != 1:
                bypassed_files.append(os.path.basename(evil_file))
            assert not os.path.exists(out_file), f"Corrupt input wrote output for {os.path.basename(evil_file)}"

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}"


def parse_datetime(dt_str):
    try:
        return datetime.fromisoformat(dt_str)
    except ValueError:
        return datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")


def process_clean_logic(input_csv):
    with open(input_csv, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        return [], 0

    parsed_rows = []
    for r in rows:
        parsed_rows.append({
            'timestamp': parse_datetime(r['timestamp']),
            'sensor_alpha': float(r['sensor_alpha']) if r['sensor_alpha'] else None,
            'sensor_beta': float(r['sensor_beta']) if r['sensor_beta'] else None,
            'sensor_gamma': float(r['sensor_gamma']) if r['sensor_gamma'] else None,
        })

    parsed_rows.sort(key=lambda x: x['timestamp'])
    start_time = parsed_rows[0]['timestamp']
    end_time = parsed_rows[-1]['timestamp']

    intervals = []
    curr = start_time
    while curr <= end_time:
        intervals.append(curr)
        curr += timedelta(minutes=5)

    sensors = ['sensor_alpha', 'sensor_beta', 'sensor_gamma']
    expected_data = []

    for sensor in sensors:
        sensor_data = {r['timestamp']: r[sensor] for r in parsed_rows if r[sensor] is not None}
        last_val = None
        ffill_count = 0

        for t in intervals:
            if t in sensor_data:
                val = sensor_data[t]
                last_val = val
                ffill_count = 0
            elif last_val is not None and ffill_count < 3:
                val = last_val
                ffill_count += 1
            else:
                val = 0.0
                last_val = None

            expected_data.append({
                'timestamp': t.strftime("%Y-%m-%d %H:%M:%S"),
                'sensor_name': sensor,
                'value': val
            })

    return expected_data, len(rows)


def assert_output_matches(out_file, expected_data):
    with open(out_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['timestamp', 'sensor_name', 'value'], \
            f"Invalid output schema/order: {reader.fieldnames}"
        out_rows = list(reader)

    assert len(out_rows) == len(expected_data), \
        f"Row count mismatch: expected {len(expected_data)}, got {len(out_rows)}"

    for index, (actual, expected) in enumerate(zip(out_rows, expected_data)):
        assert set(actual.keys()) == {'timestamp', 'sensor_name', 'value'}, \
            f"Invalid output schema at row {index}"
        assert actual['timestamp'] == expected['timestamp'], \
            f"Timestamp/order mismatch at row {index}: expected {expected['timestamp']}, got {actual['timestamp']}"
        assert actual['sensor_name'] == expected['sensor_name'], \
            f"Sensor/order mismatch at row {index}: expected {expected['sensor_name']}, got {actual['sensor_name']}"
        try:
            actual_value = float(actual['value'])
        except (TypeError, ValueError):
            pytest.fail(f"Non-numeric value at row {index}: {actual['value']!r}")
        assert actual_value == pytest.approx(float(expected['value']), rel=1e-9, abs=1e-9), \
            f"Value mismatch at row {index}: expected {expected['value']}, got {actual['value']}"


def test_native_anomaly_logic_on_derived_cases():
    with tempfile.TemporaryDirectory() as tmpdir:
        clean_file = os.path.join(tmpdir, "boundary_clean.csv")
        evil_file = os.path.join(tmpdir, "derived_evil.csv")
        clean_out = os.path.join(tmpdir, "clean_out.csv")
        evil_out = os.path.join(tmpdir, "evil_out.csv")

        with open(clean_file, 'w', newline='') as f:
            f.write("timestamp,sensor_alpha,sensor_beta,sensor_gamma\n")
            f.write("2024-02-03T00:02:00,1,10,20\n")
            f.write("2024-02-03T00:22:00,5,15,29.9\n")

        with open(evil_file, 'w', newline='') as f:
            f.write("timestamp,sensor_alpha,sensor_beta,sensor_gamma\n")
            f.write("2024-02-03T00:00:00,1,8,16\n")
            f.write("2024-02-03T00:05:00,2,7.5,15.01\n")

        backup = LEGACY_QC + ".verifier_backup"
        assert os.path.exists(LEGACY_QC), "Legacy QC binary is missing"
        os.rename(LEGACY_QC, backup)
        try:
            evil_result = subprocess.run(
                ["python3", CLEANER_SCRIPT, evil_file, evil_out], capture_output=True
            )
            clean_result = subprocess.run(
                ["python3", CLEANER_SCRIPT, clean_file, clean_out], capture_output=True
            )
        finally:
            os.rename(backup, LEGACY_QC)

        assert evil_result.returncode == 1, "A derived corrupt input was not rejected"
        assert not os.path.exists(evil_out), "A derived corrupt input wrote an output CSV"
        assert clean_result.returncode == 0, "A boundary-clean input was not processed without legacy_qc"
        assert os.path.exists(clean_out), "Boundary-clean input did not produce output"
        expected_data, _ = process_clean_logic(clean_file)
        assert_output_matches(clean_out, expected_data)


def test_clean_corpus_processed():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.csv"))
    assert len(clean_files) > 0, "No clean files found to test."

    failed_files = []

    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    with tempfile.TemporaryDirectory() as tmpdir:
        for clean_file in clean_files:
            out_file = os.path.join(tmpdir, "out.csv")
            if os.path.exists(out_file):
                os.remove(out_file)
            result = subprocess.run(
                ["python3", CLEANER_SCRIPT, clean_file, out_file],
                capture_output=True
            )

            if result.returncode != 0:
                failed_files.append((os.path.basename(clean_file), "Non-zero exit code"))
                continue

            if not os.path.exists(out_file):
                failed_files.append((os.path.basename(clean_file), "Output file not created"))
                continue

            expected_data, orig_rows = process_clean_logic(clean_file)

            try:
                assert_output_matches(out_file, expected_data)
            except AssertionError as exc:
                failed_files.append((os.path.basename(clean_file), str(exc)))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/failed: {failed_files}"


def test_log_entries():
    assert os.path.exists(LOG_FILE), f"Log file missing at {LOG_FILE}"

    with open(LOG_FILE, 'r') as f:
        log_content = f.read()
    log_lines = log_content.splitlines()

    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.csv"))
    for clean_file in clean_files:
        basename = os.path.basename(clean_file)
        expected_data, orig_rows = process_clean_logic(clean_file)
        expected_line = (
            f"[SUCCESS] Processed {basename}: "
            f"original_rows={orig_rows}, final_rows={len(expected_data)}"
        )
        assert basename in log_content, f"Log entry for {basename} not found in {LOG_FILE}"
        assert "[SUCCESS] Processed" in log_content, "Log format missing [SUCCESS] tag"
        assert expected_line in log_lines, f"Exact log entry missing: {expected_line}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
