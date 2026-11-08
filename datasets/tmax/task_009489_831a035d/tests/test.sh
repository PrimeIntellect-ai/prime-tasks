#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

SCRIPT_PATH = "/home/user/process_sensors.py"
OUTPUT_PATH = "/home/user/cleaned_telemetry.csv"
LOG_DIR = "/home/user/sensor_logs"
EXPECTED_HEADERS = ["Sensor_ID", "Log_Time", "Temperature", "Pressure"]

EXPECTED_DATA = [
    ["sensor_1", "1600000000", 20.0, 1000.0],
    ["sensor_1", "1600000010", 21.0, 1005.0],
    ["sensor_1", "1600000020", 21.0, 1010.0],
    ["sensor_1", "1600000040", 23.0, 1020.0],
    ["sensor_2", "1600000010", 15.0, 910.0],
    ["sensor_2", "1600000020", 15.0, 920.0],
    ["sensor_2", "1600000030", 16.0, 930.0],
    ["sensor_2", "1600000040", 17.0, 940.0],
    ["sensor_3", "1600000000", 10.0, 800.0],
    ["sensor_3", "1600000020", 11.0, 810.0],
    ["sensor_3", "1600000030", 12.0, 820.0],
    ["sensor_3", "1600000040", 12.0, 830.0],
    ["sensor_4", "1600000000", 5.0, 700.0],
    ["sensor_4", "1600000010", 5.5, 705.0],
    ["sensor_4", "1600000020", 6.0, 710.0],
    ["sensor_4", "1600000030", 6.0, 715.0],
    ["sensor_4", "1600000040", 7.0, 720.0],
]


def run_script(env=None):
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"Processing script failed:\n{result.stdout}"


def read_output():
    assert os.path.isfile(OUTPUT_PATH), (
        f"Output file {OUTPUT_PATH} is missing. Did the script run successfully?"
    )
    with open(OUTPUT_PATH, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, "Output CSV is empty."
    assert rows[0] == EXPECTED_HEADERS, (
        f"Headers {rows[0]} do not match expected {EXPECTED_HEADERS}."
    )
    return rows[1:]


def check_rows(actual_rows, expected_rows):
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} data rows, but found {len(actual_rows)}. "
        "Check filtering, extraction, imputation, and dropping of leading NaNs."
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows), 1):
        assert len(actual) == 4, f"Row {i} does not have 4 columns."
        assert actual[0] == expected[0], (
            f"Row {i}: Expected Sensor_ID {expected[0]!r}, got {actual[0]!r}."
        )
        assert actual[1] == expected[1], (
            f"Row {i}: Expected Log_Time {expected[1]!r}, got {actual[1]!r}."
        )
        try:
            temp = float(actual[2])
            pressure = float(actual[3])
        except ValueError:
            raise AssertionError(
                f"Row {i} contains non-numeric Temperature or Pressure: {actual}"
            )
        assert math.isfinite(temp) and math.isfinite(pressure), (
            f"Row {i} contains a missing or non-finite value: {actual}"
        )
        assert abs(temp - expected[2]) <= 1e-6, (
            f"Row {i}: Expected Temperature {expected[2]}, got {actual[2]}."
        )
        assert abs(pressure - expected[3]) <= 1e-6, (
            f"Row {i}: Expected Pressure {expected[3]}, got {actual[3]}."
        )
        assert abs(temp - round(temp, 2)) <= 1e-9, (
            f"Row {i}: Temperature is not rounded to 2 decimal places: {actual[2]}"
        )
        assert abs(pressure - round(pressure, 2)) <= 1e-9, (
            f"Row {i}: Pressure is not rounded to 2 decimal places: {actual[3]}"
        )


def make_dynamic_inputs(rng):
    generated = {}
    count = 2000
    for sensor_num in range(1, 5):
        sensor = f"sensor_{sensor_num}"
        rows = []
        base = 1700000000 + sensor_num * 100000
        for i in range(count):
            timestamp = base + i * 10
            qc = "FAIL" if i % 19 == 7 else (" PASS" if i % 43 == 9 else "PASS")
            temp_value = -18.75 + sensor_num * 5.125 + i * 0.037
            pressure_value = 875.2 + sensor_num * 23.4 + i * 0.113
            temp = "ERR" if i == 0 or i % 13 == 5 else f"{temp_value:.3f}"
            pressure = "ERR" if i == 1 or i % 17 == 8 else f"{pressure_value:.3f}"
            payload = f"PREFIX_X_T:{temp}C_MISC_Y_P:{pressure}hPa_SUFFIX"
            rows.append([str(timestamp), payload, qc])
        rng.shuffle(rows)
        generated[sensor] = rows
        path = os.path.join(LOG_DIR, sensor + ".csv")
        with open(path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Log_Time", "Raw_Payload", "QC_Flag"])
            writer.writerows(rows)
    return generated


def derive_expected(generated):
    temp_re = re.compile(r"T:(ERR|[-+]?(?:\d+(?:\.\d*)?|\.\d+))C")
    pressure_re = re.compile(r"P:(ERR|[-+]?(?:\d+(?:\.\d*)?|\.\d+))hPa")
    result = []
    for sensor in sorted(generated):
        valid = sorted(
            (row for row in generated[sensor] if row[2] == "PASS"),
            key=lambda row: int(row[0]),
        )
        values = []
        for timestamp, payload, _ in valid:
            tm = temp_re.search(payload)
            pm = pressure_re.search(payload)
            temp = None if not tm or tm.group(1) == "ERR" else float(tm.group(1))
            pressure = None if not pm or pm.group(1) == "ERR" else float(pm.group(1))
            values.append([timestamp, temp, pressure])

        last_temp = None
        for row in values:
            if row[1] is not None:
                last_temp = row[1]
            elif last_temp is not None:
                row[1] = last_temp

        known = [i for i, row in enumerate(values) if row[2] is not None]
        for left, right in zip(known, known[1:]):
            if right > left + 1:
                start = values[left][2]
                end = values[right][2]
                for pos in range(left + 1, right):
                    fraction = (pos - left) / (right - left)
                    values[pos][2] = start + (end - start) * fraction

        for timestamp, temp, pressure in values:
            if temp is not None and pressure is not None:
                result.append([sensor, timestamp, round(temp, 2), round(pressure, 2)])
    return result


def install_open_tracer(directory):
    trace_path = os.path.join(directory, "opens.log")
    sitecustomize = os.path.join(directory, "sitecustomize.py")
    with open(sitecustomize, "w") as f:
        f.write(r'''
import builtins
import os
import re
import sys

_TRACE = os.environ.get("SENSOR_OPEN_TRACE")
_LOG_DIR = os.path.realpath("/home/user/sensor_logs")
_busy = False

def _audit(event, args):
    global _busy
    if _busy or event != "open" or not _TRACE or not args:
        return
    try:
        path = os.path.realpath(os.fspath(args[0]))
    except (TypeError, ValueError):
        return
    if os.path.dirname(path) != _LOG_DIR or not re.fullmatch(r"sensor_[1-4]\.csv", os.path.basename(path)):
        return
    try:
        _busy = True
        with builtins.open(_TRACE, "a") as out:
            out.write(f"{os.getpid()}\t{os.path.basename(path)}\n")
    finally:
        _busy = False

sys.addaudithook(_audit)
''')
    return trace_path


def test_final_state_and_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH) as f:
        content = f.read()
    assert "multiprocessing" in content or "ProcessPoolExecutor" in content, (
        "Script does not appear to use multiprocessing or ProcessPoolExecutor."
    )

    # Execute against the original supplied files and retain the original exact checks.
    run_script()
    check_rows(read_output(), EXPECTED_DATA)

    backup_dir = tempfile.mkdtemp(prefix="sensor_backup_")
    for name in [f"sensor_{i}.csv" for i in range(1, 5)]:
        shutil.copy2(os.path.join(LOG_DIR, name), os.path.join(backup_dir, name))

    try:
        rng = random.Random(secrets.randbits(128))
        generated = make_dynamic_inputs(rng)
        expected = derive_expected(generated)

        with tempfile.TemporaryDirectory(prefix="sensor_trace_") as trace_dir:
            trace_path = install_open_tracer(trace_dir)
            env = os.environ.copy()
            old_pythonpath = env.get("PYTHONPATH")
            env["PYTHONPATH"] = trace_dir + (os.pathsep + old_pythonpath if old_pythonpath else "")
            env["SENSOR_OPEN_TRACE"] = trace_path

            if os.path.exists(OUTPUT_PATH):
                os.unlink(OUTPUT_PATH)
            proc = subprocess.Popen(
                [sys.executable, SCRIPT_PATH],
                cwd="/home/user",
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            output, _ = proc.communicate(timeout=60)
            assert proc.returncode == 0, f"Processing script failed on dynamic inputs:\n{output}"

            check_rows(read_output(), expected)

            events = []
            if os.path.exists(trace_path):
                with open(trace_path) as f:
                    for line in f:
                        parts = line.rstrip("\n").split("\t", 1)
                        if len(parts) == 2 and parts[0].isdigit():
                            events.append((int(parts[0]), parts[1]))
            worker_events = [(pid, name) for pid, name in events if pid != proc.pid]
            worker_pids = {pid for pid, _ in worker_events}
            worker_files = {name for _, name in worker_events}
            assert len(worker_pids) >= 2, (
                "The sensor files were not processed by multiple worker processes."
            )
            assert worker_files == {f"sensor_{i}.csv" for i in range(1, 5)}, (
                "All four CSV files must be opened and processed in worker processes; "
                f"observed worker files: {sorted(worker_files)}"
            )
    finally:
        for name in [f"sensor_{i}.csv" for i in range(1, 5)]:
            shutil.copy2(os.path.join(backup_dir, name), os.path.join(LOG_DIR, name))
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
