#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

SCRIPT_PATH = "/home/user/process_sensors.py"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"


def run_script(input_dir, out_dir, rej_dir):
    cmd = [
        "python3", SCRIPT_PATH,
        "--input", str(input_dir),
        "--output", str(out_dir),
        "--reject", str(rej_dir),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Script failed. STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Agent script not found at {SCRIPT_PATH}"


def test_clean_corpus_processing():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus missing at {CLEAN_CORPUS}"

    with tempfile.TemporaryDirectory() as out_dir, tempfile.TemporaryDirectory() as rej_dir:
        run_script(CLEAN_CORPUS, out_dir, rej_dir)

        expected_files = set(os.listdir(CLEAN_CORPUS))

        # Check output dir
        out_files = set(os.listdir(out_dir))
        # The script changes extension to .csv
        out_basenames = {os.path.splitext(f)[0] for f in out_files}
        expected_basenames = {os.path.splitext(f)[0] for f in expected_files}

        missing = expected_basenames - out_basenames

        assert not missing, f"{len(missing)} of {len(expected_files)} clean files were NOT accepted: {missing}"

        # Check reject dir
        rej_files = set(os.listdir(rej_dir))
        assert not rej_files, f"Clean files were incorrectly rejected: {rej_files}"


def test_evil_corpus_processing():
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus missing at {EVIL_CORPUS}"

    with tempfile.TemporaryDirectory() as out_dir, tempfile.TemporaryDirectory() as rej_dir:
        run_script(EVIL_CORPUS, out_dir, rej_dir)

        expected_files = set(os.listdir(EVIL_CORPUS))

        # Check reject dir
        rej_files = set(os.listdir(rej_dir))
        rej_basenames = {os.path.splitext(f)[0] for f in rej_files}
        expected_basenames = {os.path.splitext(f)[0] for f in expected_files}

        missing = expected_basenames - rej_basenames

        assert not missing, f"{len(missing)} of {len(expected_files)} evil files bypassed rejection: {missing}"

        # Check output dir
        out_files = set(os.listdir(out_dir))
        assert not out_files, f"Evil files were incorrectly accepted: {out_files}"


def write_csv(path, rows):
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["timestamp", "Sensor_ID", "value"])
        writer.writeheader()
        writer.writerows(rows)


def assert_normalized_output(path, expected_rows):
    assert path.is_file(), f"Expected normalized CSV was not created: {path}"
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == ["timestamp", "Sensor_ID", "value"], (
            f"Wrong normalized CSV columns in {path}: {reader.fieldnames}"
        )
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Wrong row count in {path}"
    actual_by_time = {}
    for row in actual_rows:
        assert set(row) == {"timestamp", "Sensor_ID", "value"}
        assert row["timestamp"] not in actual_by_time, f"Duplicate timestamp in {path}"
        try:
            value = float(row["value"])
        except (TypeError, ValueError):
            raise AssertionError(f"Non-numeric output value in {path}: {row['value']!r}")
        assert math.isfinite(value), f"Missing or non-finite output value in {path}"
        actual_by_time[row["timestamp"]] = (row["Sensor_ID"], value)

    for expected in expected_rows:
        timestamp = expected["timestamp"]
        assert timestamp in actual_by_time, f"Missing timestamp {timestamp} in {path}"
        sensor, value = actual_by_time[timestamp]
        assert sensor == expected["Sensor_ID"], f"Wrong Sensor_ID at {timestamp} in {path}"
        assert math.isclose(value, expected["value"], rel_tol=1e-8, abs_tol=1e-8), (
            f"Wrong scaled/interpolated value at {timestamp} in {path}: "
            f"got {value}, expected {expected['value']}"
        )


def test_randomized_processing_and_output_contents():
    # Names and readings are generated only when verification runs, preventing a
    # filename-based implementation from fabricating the expected artifacts.
    token = secrets.token_hex(8)
    specs = {
        "ENV_A100": (-50.0, 150.0, 1.05),
        "ENV_B200": (0.0, 500.0, 0.98),
        "ENV_C300": (-20.0, 80.0, 1.00),
    }
    cases = [
        ("ENV_A100", round(1 + secrets.randbelow(3000) / 100, 2), round(70 + secrets.randbelow(3000) / 100, 2), ""),
        ("ENV_B200", round(40 + secrets.randbelow(8000) / 100, 2), round(250 + secrets.randbelow(8000) / 100, 2), "NaN"),
        ("ENV_C300", round(-10 + secrets.randbelow(1500) / 100, 2), round(35 + secrets.randbelow(2500) / 100, 2), None),
    ]

    with tempfile.TemporaryDirectory() as root:
        root = Path(root)
        input_dir = root / "inputs"
        out_dir = root / "accepted"
        rej_dir = root / "rejected"
        input_dir.mkdir()
        out_dir.mkdir()
        rej_dir.mkdir()

        expected_outputs = {}
        for index, (sensor, first, last, missing) in enumerate(cases):
            timestamps = [
                f"2026-07-{index + 1:02d}T00:00:00",
                f"2026-07-{index + 1:02d}T01:00:00",
                f"2026-07-{index + 1:02d}T02:00:00",
            ]
            rows = [
                {"timestamp": timestamps[0], "Sensor_ID": sensor, "value": first},
                {"timestamp": timestamps[1], "Sensor_ID": sensor, "value": missing},
                {"timestamp": timestamps[2], "Sensor_ID": sensor, "value": last},
            ]
            extension = ".json" if index == 2 else ".csv"
            stem = f"live_{token}_{index}_{secrets.token_hex(4)}"
            source = input_dir / (stem + extension)
            if extension == ".json":
                source.write_text(json.dumps(rows))
            else:
                write_csv(source, rows)

            multiplier = specs[sensor][2]
            interpolated = (first + last) / 2.0
            expected_outputs[stem + ".csv"] = [
                {"timestamp": timestamps[0], "Sensor_ID": sensor, "value": first * multiplier},
                {"timestamp": timestamps[1], "Sensor_ID": sensor, "value": interpolated * multiplier},
                {"timestamp": timestamps[2], "Sensor_ID": sensor, "value": last * multiplier},
            ]

        # Randomized invalid inputs cover bounds, unknown sensors, and structure.
        bad_names = []
        bad_oob = f"bad_oob_{token}_{secrets.token_hex(4)}.csv"
        write_csv(input_dir / bad_oob, [{
            "timestamp": "2026-08-01T00:00:00",
            "Sensor_ID": "ENV_A100",
            "value": 150.01 + secrets.randbelow(10000),
        }])
        bad_names.append(bad_oob)

        bad_sensor = f"bad_sensor_{token}_{secrets.token_hex(4)}.json"
        (input_dir / bad_sensor).write_text(json.dumps([{
            "timestamp": "2026-08-02T00:00:00",
            "Sensor_ID": "UNKNOWN_" + secrets.token_hex(6),
            "value": 10.0,
        }]))
        bad_names.append(bad_sensor)

        bad_schema = f"bad_schema_{token}_{secrets.token_hex(4)}.json"
        (input_dir / bad_schema).write_text(json.dumps({"unexpected": secrets.token_hex(8)}))
        bad_names.append(bad_schema)

        run_script(input_dir, out_dir, rej_dir)

        assert set(os.listdir(out_dir)) == set(expected_outputs), (
            f"Accepted directory did not contain exactly the normalized clean files: {os.listdir(out_dir)}"
        )
        for filename, expected_rows in expected_outputs.items():
            assert_normalized_output(out_dir / filename, expected_rows)

        assert set(os.listdir(rej_dir)) == set(bad_names), (
            f"Rejected directory did not contain exactly the invalid source files: {os.listdir(rej_dir)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
