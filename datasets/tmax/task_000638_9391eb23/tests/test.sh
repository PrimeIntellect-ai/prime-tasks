#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/process_flights.sh"
LOG_PATH = "/home/user/flight_data.log"
JSON_PATH = "/home/user/closest_drone.json"

ORIGINAL_LOG = """[2023-11-01 10:15:22] INFO Drone ID: D-101 | Status: OK | Pos: 45.6000, -122.5000 | Payload: 2.5kg
[2023-11-01 10:16:00] ERROR Drone ID: D-102 | Status: OFFLINE | Connection Lost
[2023-11-01 10:17:10] INFO Drone ID: D-103 | Status: OK | Pos: 45.5500, -122.6500 | Payload: 1.0kg
[2023-11-01 10:18:05] WARNING Drone ID: D-104 | Status: LOW_BATTERY | Pos: 45.5200, -122.5900 | Payload: 1.5kg
[2023-11-01 10:19:33] INFO Drone ID: D-105 | Status: OK | Pos: 45.5100, -122.5800 | Payload: 3.2kg
[2023-11-01 10:20:00] ERROR Drone ID: D-106 | Status: CRASH | Pos: 45.5000, -122.6000 | Payload: 0.0kg
"""


def compute_expected_closest():
    assert os.path.exists(LOG_PATH), f"Log file missing at {LOG_PATH}"

    depot_lat = 45.5000
    depot_lon = -122.6000
    closest_drone = None
    min_dist = float("inf")

    with open(LOG_PATH, "r") as f:
        for line in f:
            if " INFO " in line and "Pos:" in line:
                drone_match = re.search(r"Drone ID:\s*([^\s|]+)", line)
                pos_match = re.search(r"Pos:\s*([-\d.]+),\s*([-\d.]+)", line)
                if drone_match and pos_match:
                    drone_id = drone_match.group(1)
                    lat = float(pos_match.group(1))
                    lon = float(pos_match.group(2))
                    dist = math.sqrt((lat - depot_lat) ** 2 + (lon - depot_lon) ** 2)
                    if dist < min_dist:
                        min_dist = dist
                        closest_drone = drone_id

    return closest_drone, round(min_dist, 4)


def assert_json_output_correct():
    assert os.path.exists(JSON_PATH), f"The output JSON file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file."

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    assert "closest_drone" in data, f"'closest_drone' key missing in {JSON_PATH}"
    assert "distance" in data, f"'distance' key missing in {JSON_PATH}"

    expected_drone, expected_dist = compute_expected_closest()
    assert data["closest_drone"] == expected_drone, (
        f"Expected closest_drone to be '{expected_drone}', but got '{data['closest_drone']}'. "
        "Ensure you are only considering valid INFO lines."
    )

    actual_dist = data["distance"]
    assert isinstance(actual_dist, (int, float)) and not isinstance(actual_dist, bool), (
        f"'distance' must be a number, got {type(actual_dist)}"
    )
    assert math.isclose(actual_dist, expected_dist, rel_tol=1e-4, abs_tol=1e-4), (
        f"Expected distance to be {expected_dist}, but got {actual_dist}."
    )


def run_script_and_check(log_text):
    with open(LOG_PATH, "w") as f:
        f.write(log_text)
    if os.path.lexists(JSON_PATH):
        os.unlink(JSON_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    with open(LOG_PATH, "r") as f:
        assert f.read() == log_text, "The ETL script must not modify the input flight log."
    assert_json_output_correct()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_input_log_was_not_modified():
    assert os.path.exists(LOG_PATH), f"Log file missing at {LOG_PATH}"
    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} is not a file."
    assert not os.path.islink(LOG_PATH), f"{LOG_PATH} must be the original regular file."
    with open(LOG_PATH, "r") as f:
        assert f.read() == ORIGINAL_LOG, "The supplied flight_data.log was modified."


def test_script_executes_and_generates_original_output():
    run_script_and_check(ORIGINAL_LOG)


def test_script_processes_unseen_logs():
    rng = random.SystemRandom()
    try:
        for case_num in range(2):
            ids = [f"D-{secrets.token_hex(4).upper()}" for _ in range(5)]
            positions = []
            for _ in range(3):
                lat = 45.5 + rng.uniform(-0.18, 0.18)
                lon = -122.6 + rng.uniform(-0.18, 0.18)
                positions.append((lat, lon))

            lines = [
                f"[2026-01-0{case_num + 1} 08:00:00] INFO Drone ID: {ids[0]} | Status: OK | Pos: {positions[0][0]:.6f}, {positions[0][1]:.6f} | Payload: 1.0kg",
                f"[2026-01-0{case_num + 1} 08:01:00] ERROR Drone ID: {ids[1]} | Status: CRASH | Pos: 45.500000, -122.600000 | Payload: 0.0kg",
                f"[2026-01-0{case_num + 1} 08:02:00] INFO Drone ID: {ids[2]} | Status: OK | Pos: {positions[1][0]:.6f}, {positions[1][1]:.6f} | Payload: 2.0kg",
                f"[2026-01-0{case_num + 1} 08:03:00] WARNING Drone ID: {ids[3]} | Status: LOW_BATTERY | Pos: 45.500000, -122.600000 | Payload: 1.5kg",
                f"[2026-01-0{case_num + 1} 08:04:00] INFO Drone ID: {ids[4]} | Status: OK | Pos: {positions[2][0]:.6f}, {positions[2][1]:.6f} | Payload: 3.0kg",
            ]
            run_script_and_check("\n".join(lines) + "\n")
    finally:
        with open(LOG_PATH, "w") as f:
            f.write(ORIGINAL_LOG)
        if os.path.lexists(JSON_PATH):
            os.unlink(JSON_PATH)
        subprocess.run(
            [SCRIPT_PATH], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=15, check=False
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
