#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import secrets
import subprocess
from collections import defaultdict

SCRIPT_PATH = "/home/user/process_etl.sh"
INPUT_PATH = "/home/user/data/raw_sensor.csv"
OUTPUT_PATH = "/home/user/data/daily_summary.csv"


def expected_output(input_path):
    # 1. Read and deduplicate, retaining the first occurrence.
    seen = set()
    records = []
    with open(input_path, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or len(row) < 4:
                continue
            ts, sensor, temp, hum = row[0], row[1], row[2], row[3]
            key = (ts, sensor)
            if key not in seen:
                seen.add(key)
                records.append({
                    "ts": ts,
                    "sensor": sensor,
                    "temp": float(temp) if temp.strip() else None,
                    "hum": float(hum) if hum.strip() else None,
                })

    records.sort(key=lambda x: x["ts"])

    # 2. Forward fill independently per sensor.
    last_vals = {}
    for record in records:
        sensor = record["sensor"]
        if sensor not in last_vals:
            last_vals[sensor] = {"temp": None, "hum": None}

        if record["temp"] is not None:
            last_vals[sensor]["temp"] = record["temp"]
        else:
            record["temp"] = last_vals[sensor]["temp"]

        if record["hum"] is not None:
            last_vals[sensor]["hum"] = record["hum"]
        else:
            record["hum"] = last_vals[sensor]["hum"]

    # 3. Metric calculation.
    for record in records:
        record["metric"] = record["temp"] + record["hum"] * 0.1

    # 4. Three-record rolling average per sensor.
    sensor_metrics = defaultdict(list)
    for record in records:
        metrics = sensor_metrics[record["sensor"]]
        metrics.append(record["metric"])
        window = metrics[-3:]
        record["rolling_avg"] = sum(window) / len(window)

    # 5. Daily aggregation.
    daily_sensor_avgs = defaultdict(list)
    for record in records:
        key = (record["ts"][:10], record["sensor"])
        daily_sensor_avgs[key].append(record["rolling_avg"])

    result = []
    for date, sensor in sorted(daily_sensor_avgs):
        values = daily_sensor_avgs[(date, sensor)]
        daily_mean = sum(values) / len(values)
        result.append(f"{date},{sensor},{daily_mean:.2f}")
    return result


def actual_output():
    with open(OUTPUT_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run_etl():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    completed = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"ETL script exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        f"Executing {SCRIPT_PATH} did not create {OUTPUT_PATH}."
    )


def assert_current_result():
    expected = expected_output(INPUT_PATH)
    actual = actual_output()
    assert actual == expected, (
        "Output file contents do not match expected.\n"
        f"Expected:\n{chr(10).join(expected)}\n\n"
        f"Actual:\n{chr(10).join(actual)}"
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."


def test_etl_output_correctness():
    assert os.path.isfile(INPUT_PATH), f"Input file {INPUT_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    run_etl()
    assert_current_result()


def make_altered_fixture(case_number):
    token = secrets.token_hex(4)
    sensor_a = f"A{token}"
    sensor_b = f"B{token}"
    month = case_number + 2
    day1 = f"2024-{month:02d}-11"
    day2 = f"2024-{month:02d}-12"

    def temp(base):
        return f"{base + secrets.randbelow(900) / 137.0:.3f}"

    def hum(base):
        return f"{base + secrets.randbelow(1100) / 173.0:.3f}"

    a0t, a0h = temp(14), hum(31)
    a1t, a2h = temp(17), hum(37)
    a3t, a3h = temp(19), hum(41)
    b0t, b0h = temp(21), hum(46)
    b1t, b1h = temp(23), hum(49)
    b2t, b2h = temp(25), hum(52)

    # Deliberately out of order, with conflicting duplicates and missing fields.
    rows = [
        f"{day1}T00:20:00Z,{sensor_a},,{a2h}",
        f"{day1}T00:00:00Z,{sensor_b},{b0t},{b0h}",
        f"{day1}T00:10:00Z,{sensor_a},{a1t},",
        f"{day1}T00:00:00Z,{sensor_a},{a0t},{a0h}",
        f"{day1}T00:10:00Z,{sensor_a},99.123,98.765",
        f"{day2}T01:10:00Z,{sensor_b},{b2t},{b2h}",
        f"{day1}T00:30:00Z,{sensor_b},,{b1h}",
        f"{day2}T01:00:00Z,{sensor_a},{a3t},{a3h}",
        f"{day1}T00:30:00Z,{sensor_b},{b1t},99.999",
        f"{day1}T00:00:00Z,{sensor_a},88.888,77.777",
        f"{day2}T01:00:00Z,{sensor_b},{b1t},",
    ]
    return "\n".join(rows) + "\n"


def test_etl_on_altered_inputs():
    with open(INPUT_PATH, "rb") as f:
        saved_raw = f.read()
    output_existed = os.path.isfile(OUTPUT_PATH)
    saved_output = None
    if output_existed:
        with open(OUTPUT_PATH, "rb") as f:
            saved_output = f.read()

    try:
        for case_number in range(2):
            fixture = make_altered_fixture(case_number)
            with open(INPUT_PATH, "w", newline="") as f:
                f.write(fixture)
            run_etl()
            assert_current_result()
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(saved_raw)
        if output_existed:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(saved_output)
        elif os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
