#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import re
import secrets
import subprocess
from decimal import Decimal

import pytest

PROCESSED_SENSORS_PATH = "/home/user/processed_sensors.csv"
RAW_SENSORS_PATH = "/home/user/raw_sensors.csv"
HEADER = ["timestamp", "sensor_id", "temperature", "humidity", "temp_rollavg", "hum_rollavg"]
FLOAT_RE = re.compile(r"^-?\d+\.\d{2}$")


def test_01_processed_sensors_exists():
    assert os.path.exists(PROCESSED_SENSORS_PATH), f"File {PROCESSED_SENSORS_PATH} is missing. Did you run your C++ program and output to the correct path?"
    assert os.path.isfile(PROCESSED_SENSORS_PATH), f"{PROCESSED_SENSORS_PATH} should be a file."


def test_02_processed_sensors_content():
    expected_content = """timestamp,sensor_id,temperature,humidity,temp_rollavg,hum_rollavg
1000000000,S1,20.00,50.00,20.00,50.00
1000000060,S1,21.00,52.00,20.50,51.00
1000000120,S1,22.00,54.00,21.00,52.00
1000000180,S1,23.00,56.00,21.50,53.00
1000000240,S1,24.00,58.00,22.00,54.00
1000000000,S2,10.00,80.00,10.00,80.00
1000000060,S2,12.00,82.00,11.00,81.00
1000000120,S2,14.00,84.00,12.00,82.00
1000000180,S2,16.00,86.00,13.00,83.00
1000000240,S2,18.00,88.00,14.00,84.00"""

    with open(PROCESSED_SENSORS_PATH, "r") as f:
        actual_content = f.read().strip()

    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but got {len(actual_lines)} lines in {PROCESSED_SENSORS_PATH}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i + 1}:\nExpected: {expected}\nActual:   {actual}"


def build_expected(raw_path):
    sensors = {}
    with open(raw_path, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["timestamp", "sensor_id", "temperature", "humidity"]
        for row in reader:
            sid = row["sensor_id"]
            ts = int(row["timestamp"])
            sensors.setdefault(sid, {})[ts] = {
                "temperature": Decimal(row["temperature"]) if row["temperature"] != "" else None,
                "humidity": Decimal(row["humidity"]) if row["humidity"] != "" else None,
            }

    result = []
    for sid in sorted(sensors):
        observed = sensors[sid]
        lo, hi = min(observed), max(observed)
        times = list(range(lo, hi + 1, 60))
        values = {"temperature": {}, "humidity": {}}

        for field in ("temperature", "humidity"):
            valid = sorted((t, row[field]) for t, row in observed.items() if row[field] is not None)
            assert valid[0][0] == lo and valid[-1][0] == hi
            for t in times:
                direct = observed.get(t, {}).get(field)
                if direct is not None:
                    values[field][t] = direct
                    continue
                before = max((item for item in valid if item[0] < t), key=lambda x: x[0])
                after = min((item for item in valid if item[0] > t), key=lambda x: x[0])
                ratio = Decimal(t - before[0]) / Decimal(after[0] - before[0])
                values[field][t] = before[1] + (after[1] - before[1]) * ratio

        for i, t in enumerate(times):
            window = times[max(0, i - 4):i + 1]
            temp = values["temperature"][t]
            hum = values["humidity"][t]
            temp_avg = sum((values["temperature"][x] for x in window), Decimal(0)) / Decimal(len(window))
            hum_avg = sum((values["humidity"][x] for x in window), Decimal(0)) / Decimal(len(window))
            result.append((str(t), sid, temp, hum, temp_avg, hum_avg))
    return result


def make_case(sensor_count, length):
    rng = random.SystemRandom()
    token = secrets.token_hex(4)
    rows = []
    base = 1200000000 + secrets.randbelow(2000000) * 60

    for s in range(sensor_count):
        sid = f"D{chr(65 + s)}_{token}_{secrets.token_hex(2)}"
        sensor_base = base + s * 6000
        temps = [Decimal(10 + secrets.randbelow(30))]
        hums = [Decimal(35 + secrets.randbelow(45))]
        for _ in range(1, length):
            temps.append(temps[-1] + Decimal(secrets.randbelow(8) - 3))
            hums.append(hums[-1] + Decimal(secrets.randbelow(9) - 4))

        omitted = {1, 2, length - 4}
        temp_blank = {3, length - 2}
        hum_blank = {4, length - 3}
        for i in range(length):
            if i in omitted:
                continue
            temp = "" if i in temp_blank else str(temps[i])
            hum = "" if i in hum_blank else str(hums[i])
            if i == 0 or i == length - 1:
                temp, hum = str(temps[i]), str(hums[i])
            rows.append([str(sensor_base + i * 60), sid, temp, hum])

    rng.shuffle(rows)
    return rows


def write_case(rows):
    with open(RAW_SENSORS_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["timestamp", "sensor_id", "temperature", "humidity"])
        writer.writerows(rows)


def validate_dynamic_output(expected):
    assert os.path.isfile(PROCESSED_SENSORS_PATH), "Program did not create processed_sensors.csv"
    with open(PROCESSED_SENSORS_PATH, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, "Output is empty"
    assert rows[0] == HEADER, f"Incorrect output header: {rows[0]}"
    actual = rows[1:]
    assert len(actual) == len(expected), f"Expected {len(expected)} data rows, got {len(actual)}"

    for index, (row, exp) in enumerate(zip(actual, expected), start=2):
        assert len(row) == 6, f"Line {index} does not have 6 columns"
        assert row[0] == exp[0] and row[1] == exp[1], f"Incorrect ordering or identity at line {index}"
        for column in range(2, 6):
            assert FLOAT_RE.fullmatch(row[column]), f"Line {index}, column {column + 1} is not formatted to exactly two decimal places"
            error = abs(Decimal(row[column]) - exp[column])
            assert error <= Decimal("0.0051"), f"Incorrect value at line {index}, column {column + 1}: got {row[column]}, expected {exp[column]}"


def test_03_cpp_pipeline_on_additional_inputs():
    sources = sorted(set(
        glob.glob("/home/user/**/*.cpp", recursive=True)
        + glob.glob("/home/user/**/*.cc", recursive=True)
        + glob.glob("/home/user/**/*.cxx", recursive=True)
    ))
    sources = [p for p in sources if os.path.isfile(p)]
    assert sources, "No C++ source file was written under /home/user"

    compile_groups = [[source] for source in sources]
    if len(sources) > 1:
        compile_groups.append(sources)

    binaries = []
    compile_errors = []
    for i, group in enumerate(compile_groups):
        binary = f"/tmp/sensor_pipeline_{i}"
        result = subprocess.run(
            ["g++", "-O3", "-std=c++17", *group, "-o", binary],
            cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=45
        )
        if result.returncode == 0:
            binaries.append(binary)
        else:
            compile_errors.append(result.stderr[-2000:])
    assert binaries, "No submitted C++ source could be compiled:\n" + "\n".join(compile_errors)

    with open(RAW_SENSORS_PATH, "rb") as f:
        original_raw = f.read()
    with open(PROCESSED_SENSORS_PATH, "rb") as f:
        original_processed = f.read()

    cases = [make_case(2, 9), make_case(3, 11)]
    failures = []
    passed = False
    try:
        for binary in binaries:
            candidate_ok = True
            for case_number, rows in enumerate(cases, start=1):
                try:
                    write_case(rows)
                    expected = build_expected(RAW_SENSORS_PATH)
                    if os.path.exists(PROCESSED_SENSORS_PATH):
                        os.remove(PROCESSED_SENSORS_PATH)
                    run = subprocess.run(
                        [binary], cwd="/home/user", stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True, timeout=15
                    )
                    assert run.returncode == 0, f"program exited with status {run.returncode}: {run.stderr[-1000:]}"
                    validate_dynamic_output(expected)
                except Exception as exc:
                    candidate_ok = False
                    failures.append(f"{binary}, case {case_number}: {exc}")
                    break
            if candidate_ok:
                passed = True
                break
    finally:
        with open(RAW_SENSORS_PATH, "wb") as f:
            f.write(original_raw)
        with open(PROCESSED_SENSORS_PATH, "wb") as f:
            f.write(original_processed)

    assert passed, "No compiled C++ pipeline passed the additional inputs:\n" + "\n".join(failures[-10:])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
