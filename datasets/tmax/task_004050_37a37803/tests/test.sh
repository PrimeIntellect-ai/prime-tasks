#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import secrets
import subprocess
from collections import defaultdict

SOURCE = "/home/user/process_sensors.c"
EXECUTABLE = "/home/user/process_sensors"
INPUT = "/home/user/sensors.csv"
OUTPUT = "/home/user/summary.csv"
REBUILT = "/tmp/process_sensors_rebuilt"


def expected_rows(input_path):
    sensor_temps = defaultdict(list)
    with open(input_path, "r", newline="") as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            if not row or len(row) < 4:
                continue

            sensor_id = int(row[1])
            temp = float(row[2])
            err_str = row[3]
            err_code = -1 if err_str.strip() == "" else int(err_str)

            if temp < -50.0 or temp > 150.0:
                continue
            if err_code not in (0, -1):
                continue
            sensor_temps[sensor_id].append(temp)

    result = [["sensor_id", "avg_temperature"]]
    for sid in sorted(sensor_temps):
        temps = sensor_temps[sid]
        result.append([str(sid), f"{sum(temps) / len(temps):.2f}"])
    return result


def read_actual_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    with open(OUTPUT, "r", newline="") as f:
        actual = list(csv.reader(f))
    assert len(actual) > 0, "Output CSV is empty."
    assert actual[0] == ["sensor_id", "avg_temperature"], f"Incorrect header in summary.csv: {actual[0]}"
    return actual


def assert_output_matches_input():
    expected = expected_rows(INPUT)
    actual = read_actual_output()
    assert len(actual) == len(expected), f"Expected {len(expected)} rows in summary.csv, got {len(actual)}"
    for i, (expected_row, actual_row) in enumerate(zip(expected, actual)):
        assert expected_row == actual_row, f"Row {i} mismatch. Expected {expected_row}, got {actual_row}"


def test_c_source_exists():
    assert os.path.isfile(SOURCE), "C source file /home/user/process_sensors.c is missing."


def test_summary_csv_exists():
    assert os.path.isfile(OUTPUT), "Output file /home/user/summary.csv is missing."


def test_summary_csv_contents():
    assert os.path.isfile(INPUT), f"Input file {INPUT} is missing."
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    assert_output_matches_input()


def test_compiled_program_exists():
    assert os.path.isfile(EXECUTABLE), "Compiled program /home/user/process_sensors is missing."
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/process_sensors is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/process_sensors is not a compiled ELF executable."


def make_case():
    rng = secrets.SystemRandom()
    ids = rng.sample(range(1000, 1000000), 5)
    a, b, c, d, e = ids
    base = rng.randint(-20, 80)
    rows = [
        ["2026-01-01T00:00:00Z", a, f"{base + 2}.00", ""],
        ["2026-01-01T00:00:01Z", a, f"{base + 4}.00", "0"],
        ["2026-01-01T00:00:02Z", b, "-50.00", ""],
        ["2026-01-01T00:00:03Z", b, "150.00", "0"],
        ["2026-01-01T00:00:04Z", c, "12.00", "-1"],
        ["2026-01-01T00:00:05Z", c, "-50.25", "0"],
        ["2026-01-01T00:00:06Z", c, "150.25", ""],
        ["2026-01-01T00:00:07Z", d, "33.00", "1"],
        ["2026-01-01T00:00:08Z", d, "44.00", "404"],
        ["2026-01-01T00:00:09Z", e, "-10.00", ""],
        ["2026-01-01T00:00:10Z", e, "20.00", "0"],
    ]
    rng.shuffle(rows)
    return rows


def write_case(rows):
    with open(INPUT, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "sensor_id", "temperature", "error_code"])
        writer.writerows(rows)


def run_and_verify(program, rows):
    write_case(rows)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    completed = subprocess.run([program], cwd="/home/user", stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, timeout=5)
    assert completed.returncode == 0, (
        f"{program} exited with status {completed.returncode}. stderr: {completed.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{program} did not create /home/user/summary.csv"
    assert_output_matches_input()


def test_program_executes_and_processes_new_inputs():
    compile_result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", REBUILT, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert compile_result.returncode == 0, f"process_sensors.c does not compile: {compile_result.stderr}"

    # Exercise both the submitted executable and a fresh build from the submitted source.
    for program in (EXECUTABLE, REBUILT):
        run_and_verify(program, make_case())
        run_and_verify(program, make_case())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
