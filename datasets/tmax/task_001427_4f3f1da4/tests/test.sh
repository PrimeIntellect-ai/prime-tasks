#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import random
import secrets
import shutil
import subprocess
import tempfile
import pytest

SENSORS_FILE = "/home/user/sensors.csv"
RESULTS_FILE = "/home/user/results.csv"
PROCESS_FILE = "/home/user/process"
SOURCE_FILE = "/home/user/process.go"


def expected_from_sensors(sensors):
    expected_results = []
    for i, s in enumerate(sensors):
        prior_fail = s["prior_fail"]
        prior_ok = 1.0 - prior_fail

        if s["is_high"] == 1:
            likelihood_fail = s["p_high_given_fail"]
            likelihood_ok = s["p_high_given_ok"]
        else:
            likelihood_fail = 1.0 - s["p_high_given_fail"]
            likelihood_ok = 1.0 - s["p_high_given_ok"]

        marginal = (likelihood_fail * prior_fail) + (likelihood_ok * prior_ok)
        posterior = (likelihood_fail * prior_fail) / marginal

        nearest_id = None
        min_dist = float("inf")
        for j, other in enumerate(sensors):
            if i == j:
                continue
            dist = math.hypot(s["val_x"] - other["val_x"], s["val_y"] - other["val_y"])
            if dist < min_dist:
                min_dist = dist
                nearest_id = other["sensor_id"]

        expected_results.append({
            "sensor_id": s["sensor_id"],
            "posterior_fail_prob": f"{posterior:.4f}",
            "nearest_sensor_id": nearest_id,
        })
    return expected_results


def read_results(path):
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["sensor_id", "posterior_fail_prob", "nearest_sensor_id"], "Results CSV header is incorrect"
        return list(reader)


def assert_results_match(actual_results, expected_results):
    assert len(actual_results) == len(expected_results), "Number of rows in results.csv does not match sensors.csv"
    for expected, actual in zip(expected_results, actual_results):
        assert actual["sensor_id"] == expected["sensor_id"], f"Expected sensor_id {expected['sensor_id']}, got {actual['sensor_id']}"
        assert actual["posterior_fail_prob"] == expected["posterior_fail_prob"], f"Incorrect posterior probability for {expected['sensor_id']}"
        assert actual["nearest_sensor_id"] == expected["nearest_sensor_id"], f"Incorrect nearest neighbor for {expected['sensor_id']}"


def test_process_go_exists():
    assert os.path.isfile(SOURCE_FILE), "/home/user/process.go is missing"


def test_process_executable_exists():
    assert os.path.isfile(PROCESS_FILE), "/home/user/process executable is missing"
    assert os.access(PROCESS_FILE, os.X_OK), "/home/user/process is not executable"


def test_results_csv_correct():
    assert os.path.isfile(SENSORS_FILE), f"{SENSORS_FILE} is missing"
    assert os.path.isfile(RESULTS_FILE), f"{RESULTS_FILE} is missing"

    sensors = []
    with open(SENSORS_FILE, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            sensors.append({
                "sensor_id": row["sensor_id"],
                "val_x": float(row["val_x"]),
                "val_y": float(row["val_y"]),
                "prior_fail": float(row["prior_fail"]),
                "p_high_given_fail": float(row["p_high_given_fail"]),
                "p_high_given_ok": float(row["p_high_given_ok"]),
                "is_high": int(row["is_high"]),
            })

    expected_results = expected_from_sensors(sensors)
    actual_results = read_results(RESULTS_FILE)
    assert_results_match(actual_results, expected_results)


def make_random_fixture(rng):
    while True:
        count = rng.randint(4, 8)
        coords = set()
        while len(coords) < count:
            coords.add((rng.randint(-500, 500), rng.randint(-500, 500)))
        coords = list(coords)

        # Reject coordinate sets with tied nearest-neighbor distances so the
        # required single neighbor is unambiguous.
        unambiguous = True
        for i, (x, y) in enumerate(coords):
            distances = []
            for j, (ox, oy) in enumerate(coords):
                if i != j:
                    distances.append((x - ox) ** 2 + (y - oy) ** 2)
            distances.sort()
            if len(distances) > 1 and distances[0] == distances[1]:
                unambiguous = False
                break
        if unambiguous:
            break

    prefix = secrets.token_hex(6)
    sensors = []
    for i, (x, y) in enumerate(coords):
        sensors.append({
            "sensor_id": f"R_{prefix}_{i}",
            "val_x": float(x) + rng.randint(1, 99) / 100.0,
            "val_y": float(y) + rng.randint(1, 99) / 100.0,
            "prior_fail": rng.randint(20, 900) / 1000.0,
            "p_high_given_fail": rng.randint(100, 980) / 1000.0,
            "p_high_given_ok": rng.randint(20, 900) / 1000.0,
            "is_high": i % 2,
        })
    return sensors


def write_fixture(sensors):
    with open(SENSORS_FILE, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["sensor_id", "val_x", "val_y", "prior_fail", "p_high_given_fail", "p_high_given_ok", "is_high"])
        for s in sensors:
            writer.writerow([
                s["sensor_id"], s["val_x"], s["val_y"], s["prior_fail"],
                s["p_high_given_fail"], s["p_high_given_ok"], s["is_high"],
            ])


def run_and_check(binary, sensors):
    write_fixture(sensors)
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    completed = subprocess.run(
        [binary], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert completed.returncode == 0, f"{binary} failed: {completed.stderr}"
    assert os.path.isfile(RESULTS_FILE), f"{binary} did not generate /home/user/results.csv"
    assert_results_match(read_results(RESULTS_FILE), expected_from_sensors(sensors))


def test_go_program_executes_on_unseen_inputs():
    version_check = subprocess.run(
        ["go", "version", "-m", PROCESS_FILE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert version_check.returncode == 0 and "go1" in version_check.stdout, "/home/user/process is not a compiled Go executable"

    original_sensors = open(SENSORS_FILE, "rb").read()
    original_results = open(RESULTS_FILE, "rb").read() if os.path.exists(RESULTS_FILE) else None
    build_dir = tempfile.mkdtemp(prefix="verify-go-")
    rebuilt_process = os.path.join(build_dir, "process-from-source")

    try:
        build = subprocess.run(
            ["go", "build", "-o", rebuilt_process, SOURCE_FILE],
            cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30
        )
        assert build.returncode == 0, f"process.go does not compile: {build.stderr}"

        rng = random.SystemRandom()
        for _ in range(3):
            sensors = make_random_fixture(rng)
            run_and_check(PROCESS_FILE, sensors)
            run_and_check(rebuilt_process, sensors)
    finally:
        with open(SENSORS_FILE, "wb") as f:
            f.write(original_sensors)
        if original_results is None:
            if os.path.exists(RESULTS_FILE):
                os.remove(RESULTS_FILE)
        else:
            with open(RESULTS_FILE, "wb") as f:
                f.write(original_results)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
