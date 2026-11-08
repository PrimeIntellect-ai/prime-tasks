#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import pytest
import subprocess
import sys
import secrets
import stat
from datetime import datetime, timedelta

BASE = "/home/user/factory_data"
RUN_SCRIPT = os.path.join(BASE, "run_pipeline.sh")
EXTRACT_SCRIPT = os.path.join(BASE, "extract.py")
PROCESS_SCRIPT = os.path.join(BASE, "process.py")
CSV_FILE = os.path.join(BASE, "extracted_logs.csv")
JSONL_FILE = os.path.join(BASE, "final_metrics.jsonl")
LOG_FILE = os.path.join(BASE, "maintenance_logs.txt")
SENSOR_FILE = os.path.join(BASE, "sensor_telemetry.csv")


def test_pipeline_scripts_exist_and_executable():
    run_script = "/home/user/factory_data/run_pipeline.sh"
    extract_script = "/home/user/factory_data/extract.py"
    process_script = "/home/user/factory_data/process.py"

    assert os.path.isfile(run_script), f"{run_script} is missing"
    assert os.access(run_script, os.X_OK), f"{run_script} is not executable"

    assert os.path.isfile(extract_script), f"{extract_script} is missing"
    assert os.path.isfile(process_script), f"{process_script} is missing"


def test_pipeline_executes_on_original_inputs():
    for path in (CSV_FILE, JSONL_FILE):
        if os.path.exists(path):
            os.remove(path)
    subprocess.run([RUN_SCRIPT], cwd=BASE, check=True, timeout=30)
    assert os.path.isfile(CSV_FILE), f"{CSV_FILE} was not created by run_pipeline.sh"
    assert os.path.isfile(JSONL_FILE), f"{JSONL_FILE} was not created by run_pipeline.sh"


def test_extracted_logs_csv_correctness():
    csv_file = "/home/user/factory_data/extracted_logs.csv"
    assert os.path.isfile(csv_file), f"{csv_file} is missing"

    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert reader.fieldnames == ["timestamp", "machine_id", "error_code", "downtime_minutes"], \
        "extracted_logs.csv does not have the correct header"

    expected_rows = [
        {"timestamp": "2023-11-01 10:15:00", "machine_id": "Mach-101", "error_code": "E12", "downtime_minutes": "45"},
        {"timestamp": "2023-11-01 14:30:00", "machine_id": "Mach-204", "error_code": "E99", "downtime_minutes": "120"},
        {"timestamp": "2023-11-02 09:00:00", "machine_id": "Mach-101", "error_code": "E01", "downtime_minutes": "30"},
        {"timestamp": "2023-11-02 11:00:00", "machine_id": "Mach-300", "error_code": "E44", "downtime_minutes": "60"},
    ]

    assert len(rows) == len(expected_rows), "extracted_logs.csv row count mismatch"
    for i, (row, expected) in enumerate(zip(rows, expected_rows)):
        assert row == expected, f"extracted_logs.csv row {i} mismatch. Expected {expected}, got {row}"


def test_final_metrics_jsonl_correctness():
    jsonl_file = "/home/user/factory_data/final_metrics.jsonl"
    assert os.path.isfile(jsonl_file), f"{jsonl_file} is missing"

    with open(jsonl_file, 'r', encoding='utf-8') as f:
        lines = f.read().strip().split('\n')

    expected_data = [
        {"event_timestamp": "2023-11-01 10:15:00", "machine_id": "Mach-101", "error_code": "E12", "downtime_minutes": 45, "avg_temperature": 47.83, "avg_vibration": 0.5},
        {"event_timestamp": "2023-11-01 14:30:00", "machine_id": "Mach-204", "error_code": "E99", "downtime_minutes": 120, "avg_temperature": 62.33, "avg_vibration": 1.27},
        {"event_timestamp": "2023-11-02 09:00:00", "machine_id": "Mach-101", "error_code": "E01", "downtime_minutes": 30, "avg_temperature": 44.5, "avg_vibration": 0.18},
        {"event_timestamp": "2023-11-02 11:00:00", "machine_id": "Mach-300", "error_code": "E44", "downtime_minutes": 60, "avg_temperature": None, "avg_vibration": None}
    ]

    assert len(lines) == len(expected_data), "final_metrics.jsonl row count mismatch"

    for i, (line, expected) in enumerate(zip(lines, expected_data)):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i} in final_metrics.jsonl is not valid JSON")

        expected_keys = {"event_timestamp", "machine_id", "error_code", "downtime_minutes", "avg_temperature", "avg_vibration"}
        assert set(parsed.keys()) == expected_keys, f"Line {i} keys mismatch. Expected {expected_keys}, got {set(parsed.keys())}"

        assert parsed["event_timestamp"] == expected["event_timestamp"], f"Line {i} event_timestamp mismatch"
        assert parsed["machine_id"] == expected["machine_id"], f"Line {i} machine_id mismatch"
        assert parsed["error_code"] == expected["error_code"], f"Line {i} error_code mismatch"
        assert parsed["downtime_minutes"] == expected["downtime_minutes"], f"Line {i} downtime_minutes mismatch"

        if expected["avg_temperature"] is None:
            assert parsed["avg_temperature"] is None, f"Line {i} avg_temperature should be null"
        else:
            assert abs(parsed["avg_temperature"] - expected["avg_temperature"]) < 0.01, f"Line {i} avg_temperature mismatch"

        if expected["avg_vibration"] is None:
            assert parsed["avg_vibration"] is None, f"Line {i} avg_vibration should be null"
        else:
            assert abs(parsed["avg_vibration"] - expected["avg_vibration"]) < 0.01, f"Line {i} avg_vibration mismatch"


def read_extracted():
    with open(CSV_FILE, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    assert reader.fieldnames == ["timestamp", "machine_id", "error_code", "downtime_minutes"]
    return rows


def read_metrics():
    with open(JSONL_FILE, encoding='utf-8') as f:
        lines = [line for line in f.read().splitlines() if line.strip()]
    return [json.loads(line) for line in lines]


def test_scripts_and_pipeline_on_runtime_generated_inputs():
    token = secrets.randbelow(700000) + 200000
    machine1 = f"Mach-{token}"
    machine2 = f"Mach-{token + 1}"
    other_machine = f"Mach-{token + 2}"
    code1 = f"E{secrets.randbelow(80) + 10}"
    code2 = f"E{secrets.randbelow(80) + 110}"
    down1 = secrets.randbelow(80) + 11
    down2 = secrets.randbelow(80) + 101
    event1 = datetime(2024, secrets.randbelow(10) + 1, secrets.randbelow(20) + 5, 12, 17, 0)
    event2 = event1 + timedelta(hours=5, minutes=26)
    fmt = lambda value: value.strftime("%Y-%m-%d %H:%M:%S")

    with open(LOG_FILE, 'w', encoding='utf-8') as f:
        f.write(f"{fmt(event1)} - Inspection of {machine1} completed. ErrCode:{code1}. Resulted in {down1} minutes downtime.\n")
        f.write(f"{fmt(event2)} - Emergency repair on {machine2}; ErrCode:{code2}; {down2} minutes downtime.\n")

    expected_csv = [
        {"timestamp": fmt(event1), "machine_id": machine1, "error_code": code1, "downtime_minutes": str(down1)},
        {"timestamp": fmt(event2), "machine_id": machine2, "error_code": code2, "downtime_minutes": str(down2)},
    ]

    if os.path.exists(CSV_FILE):
        os.remove(CSV_FILE)
    subprocess.run([sys.executable, EXTRACT_SCRIPT], cwd=BASE, check=True, timeout=30)
    assert read_extracted() == expected_csv

    temp_base = float(secrets.randbelow(25) + 30)
    vib_base = (secrets.randbelow(20) + 5) / 10.0
    included = [
        (event1 - timedelta(hours=3), temp_base + 0.1, vib_base + 0.1),
        (event1 - timedelta(hours=2), temp_base + 1.2, vib_base + 0.4),
        (event1 - timedelta(minutes=1), temp_base + 2.4, vib_base + 0.8),
    ]
    sensor_rows = [
        (event1 - timedelta(hours=3, seconds=1), machine1, temp_base + 90, vib_base + 9),
        *[(ts, machine1, temp, vib) for ts, temp, vib in included],
        (event1, machine1, temp_base + 80, vib_base + 8),
        (event1 - timedelta(hours=1), other_machine, temp_base + 70, vib_base + 7),
    ]
    with open(SENSOR_FILE, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "machine_id", "temperature", "vibration"])
        for ts, machine, temp, vib in sensor_rows:
            writer.writerow([fmt(ts), machine, temp, vib])

    avg_temp = round(sum(row[1] for row in included) / len(included), 2)
    avg_vib = round(sum(row[2] for row in included) / len(included), 2)
    expected_metrics = [
        {"event_timestamp": fmt(event1), "machine_id": machine1, "error_code": code1, "downtime_minutes": down1, "avg_temperature": avg_temp, "avg_vibration": avg_vib},
        {"event_timestamp": fmt(event2), "machine_id": machine2, "error_code": code2, "downtime_minutes": down2, "avg_temperature": None, "avg_vibration": None},
    ]

    if os.path.exists(JSONL_FILE):
        os.remove(JSONL_FILE)
    subprocess.run([sys.executable, PROCESS_SCRIPT], cwd=BASE, check=True, timeout=30)
    assert read_metrics() == expected_metrics

    for path in (CSV_FILE, JSONL_FILE):
        if os.path.exists(path):
            os.remove(path)
    subprocess.run([RUN_SCRIPT], cwd=BASE, check=True, timeout=30)
    assert read_extracted() == expected_csv
    assert read_metrics() == expected_metrics


def test_orchestrator_invokes_extract_then_process():
    marker = os.path.join(BASE, ".pipeline_order_marker")
    originals = {}
    for path in (EXTRACT_SCRIPT, PROCESS_SCRIPT):
        with open(path, 'rb') as f:
            originals[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))

    extract_probe = f'''#!/usr/bin/env python3
with open({marker!r}, "w", encoding="utf-8") as f:
    f.write("extract\\n")
'''
    process_probe = f'''#!/usr/bin/env python3
with open({marker!r}, "r", encoding="utf-8") as f:
    assert f.read() == "extract\\n", "process.py ran before extract.py"
with open({marker!r}, "a", encoding="utf-8") as f:
    f.write("process\\n")
'''

    try:
        if os.path.exists(marker):
            os.remove(marker)
        with open(EXTRACT_SCRIPT, 'w', encoding='utf-8') as f:
            f.write(extract_probe)
        with open(PROCESS_SCRIPT, 'w', encoding='utf-8') as f:
            f.write(process_probe)
        os.chmod(EXTRACT_SCRIPT, 0o755)
        os.chmod(PROCESS_SCRIPT, 0o755)
        subprocess.run([RUN_SCRIPT], cwd=BASE, check=True, timeout=30)
        with open(marker, encoding='utf-8') as f:
            assert f.read() == "extract\nprocess\n"
    finally:
        for path, (content, mode) in originals.items():
            with open(path, 'wb') as f:
                f.write(content)
            os.chmod(path, mode)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
