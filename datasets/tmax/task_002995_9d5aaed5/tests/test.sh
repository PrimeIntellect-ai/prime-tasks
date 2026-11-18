#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_sensor_processor.py
import csv
import math
import os
import random
import re
import subprocess

INPUT = "/home/user/sensor_data.csv"
OUTPUT = "/home/user/anomalies.csv"
PROJECT = "/home/user/sensor_processor"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
HEADERS = ["timestamp", "sensor_id", "value", "delta"]
DELTA_FORMAT = re.compile(r"^\d+\.\d$")


def expected_anomalies(path):
    anomalies = []
    counts = {}
    previous = {}

    with open(path, newline="") as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration:
            raise AssertionError(f"Input file {path} is empty")
        assert header == ["timestamp", "sensor_id", "value"], f"Unexpected input header: {header}"

        for row in reader:
            # Rows not containing exactly the three declared fields are malformed.
            if len(row) != 3:
                continue
            timestamp, sensor, value_text = row
            try:
                int(timestamp)
                value = float(value_text)
            except ValueError:
                continue
            if not sensor or not math.isfinite(value):
                continue
            if value < -50.0 or value > 150.0:
                continue

            count = counts.get(sensor, 0)
            counts[sensor] = count + 1
            if count % 5 != 0:
                continue

            if sensor in previous:
                delta = abs(value - previous[sensor])
                if delta > 20.0:
                    anomalies.append((timestamp, sensor, value, f"{delta:.1f}"))
            previous[sensor] = value

    return anomalies


def assert_output(expected):
    assert os.path.isfile(OUTPUT), f"The expected output file {OUTPUT} is missing."
    with open(OUTPUT, newline="") as handle:
        reader = csv.reader(handle)
        try:
            headers = next(reader)
        except StopIteration:
            raise AssertionError(f"The file {OUTPUT} is empty.")
        assert headers == HEADERS, f"Headers in {OUTPUT} are incorrect. Expected {HEADERS}, got {headers}."

        actual = []
        for row in reader:
            if not row:
                continue
            assert len(row) == 4, f"Row {row} does not have exactly 4 columns."
            assert DELTA_FORMAT.fullmatch(row[3]), f"Delta {row[3]!r} is not formatted to exactly one decimal place."
            try:
                value = float(row[2])
                delta = float(row[3])
            except ValueError as exc:
                raise AssertionError(f"Output row contains a non-numeric value: {row}") from exc
            assert math.isfinite(value) and math.isfinite(delta), f"Output row contains a non-finite value: {row}"
            actual.append((row[0], row[1], value, row[3]))

    assert len(actual) == len(expected), f"Expected {len(expected)} anomalies, but found {len(actual)}."
    for index, (got, wanted) in enumerate(zip(actual, expected), 1):
        assert got[0] == wanted[0], f"Row {index}: expected timestamp {wanted[0]}, got {got[0]}."
        assert got[1] == wanted[1], f"Row {index}: expected sensor_id {wanted[1]}, got {got[1]}."
        assert got[2] == wanted[2], f"Row {index}: expected value {wanted[2]}, got {got[2]}."
        assert got[3] == wanted[3], f"Row {index}: expected delta {wanted[3]}, got {got[3]}."


def make_case(case_number):
    rng = random.SystemRandom()
    sensors = [f"D{case_number}_{i}_{rng.randrange(10000, 99999)}" for i in range(3)]
    timestamp = rng.randrange(200000, 800000)
    lines = ["timestamp,sensor_id,value"]

    # These malformed and out-of-range rows must not advance a sensor's counter.
    for sensor in sensors:
        lines.append(f"not_an_integer,{sensor},33.0")
        lines.append(f"{timestamp},{sensor},151.0")
        timestamp += 1
        lines.append(f"{timestamp},{sensor},not_a_float")
        timestamp += 1
        lines.append(f"{timestamp},{sensor},20.0,extra_field")
        timestamp += 1

    for index in range(16):
        order = sensors[:]
        rng.shuffle(order)
        for sensor in order:
            if index == 0:
                value = float(rng.randrange(0, 11))
            elif index == 5:
                value = float(rng.randrange(90, 111))
            elif index == 10:
                value = float(rng.randrange(-10, 11))
            elif index == 15:
                value = float(rng.randrange(110, 141))
            elif index == 2:
                value = -50.0
            elif index == 3:
                value = 150.0
            else:
                value = rng.randrange(-400, 1401) / 10.0
            lines.append(f"{timestamp},{sensor},{value:.1f}")
            timestamp += 1

        # Invalid rows interspersed with valid data also must not affect sampling.
        sensor = rng.choice(sensors)
        invalid = rng.choice([-50.1, 150.1, 999.0])
        lines.append(f"{timestamp},{sensor},{invalid:.1f}")
        timestamp += 1

    return "\n".join(lines) + "\n"


def run_program():
    result = subprocess.run(
        ["/usr/bin/cargo", "run", "--quiet", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Rust program failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def main():
    assert os.path.isfile(INPUT), f"Input file {INPUT} is missing."

    original_input = open(INPUT, "rb").read()
    output_existed = os.path.isfile(OUTPUT)
    original_output = open(OUTPUT, "rb").read() if output_existed else None

    try:
        # Preserve the original verifier's assertions on the agent-produced file.
        assert_output(expected_anomalies(INPUT))

        assert os.path.isdir(PROJECT), f"Rust project directory {PROJECT} is missing."
        assert os.path.isfile(MANIFEST), f"Cargo manifest {MANIFEST} is missing."
        rust_sources = []
        for root, dirs, files in os.walk(PROJECT):
            dirs[:] = [d for d in dirs if d != "target"]
            rust_sources.extend(os.path.join(root, name) for name in files if name.endswith(".rs"))
        assert rust_sources, f"No Rust source files were found in {PROJECT}."
        assert any(os.path.getsize(path) > 0 for path in rust_sources), "All Rust source files are empty."

        build = subprocess.run(
            ["/usr/bin/cargo", "build", "--quiet", "--manifest-path", MANIFEST],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        assert build.returncode == 0, (
            f"The Rust project does not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
        )

        # Exercise the compiled Rust program on fresh, unpredictable datasets.
        for case_number in range(3):
            with open(INPUT, "w", newline="") as handle:
                handle.write(make_case(case_number))
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
            expected = expected_anomalies(INPUT)
            assert expected, "Internal test case unexpectedly contains no anomalies."
            run_program()
            assert_output(expected)
    finally:
        with open(INPUT, "wb") as handle:
            handle.write(original_input)
        if output_existed:
            with open(OUTPUT, "wb") as handle:
                handle.write(original_output)
        elif os.path.exists(OUTPUT):
            os.remove(OUTPUT)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_sensor_processor.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
