#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import secrets
import shutil
import subprocess
import uuid

import pytest

JSON_PATH = "/home/user/movement_summary.json"
LOG_PATH = "/home/user/pipeline.log"
SOURCE_PATH = "/home/user/drone_tracker.cpp"
T1_PATH = "/home/user/t1_positions.csv"
T2_PATH = "/home/user/t2_positions.csv"
VERIFIED_BINARY = "/tmp/drone_tracker_verified"


def test_movement_summary_json():
    assert os.path.isfile(JSON_PATH), f"JSON file {JSON_PATH} does not exist. The C++ program may not have run or failed to create it."

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "matched_drones" in data, "Key 'matched_drones' missing in JSON."
    assert "average_distance" in data, "Key 'average_distance' missing in JSON."
    assert "max_distance_id" in data, "Key 'max_distance_id' missing in JSON."

    assert data["matched_drones"] == 3, f"Expected 3 matched_drones, got {data['matched_drones']}"
    assert data["max_distance_id"] == "D05", f"Expected max_distance_id 'D05', got {data['max_distance_id']}"
    assert math.isclose(data["average_distance"], 5.0, rel_tol=1e-2), f"Expected average_distance around 5.0, got {data['average_distance']}"


def test_pipeline_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."

    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    expected_lines = [
        "[INFO] Read 4 records from t1",
        "[INFO] Read 5 records from t2",
        "[INFO] Computed distances for 3 drones",
        "[INFO] Results written to JSON"
    ]

    for line in expected_lines:
        assert line in log_content, f"Expected log line '{line}' not found in {LOG_PATH}"


def _csv_text(rows):
    return "id,x,y,z\n" + "".join(
        f"{drone_id},{x},{y},{z}\n" for drone_id, x, y, z in rows
    )


def _run_case(t1_rows, t2_rows, expected_distances):
    with open(T1_PATH, "w") as f:
        f.write(_csv_text(t1_rows))
    with open(T2_PATH, "w") as f:
        f.write(_csv_text(t2_rows))

    for path in (JSON_PATH, LOG_PATH):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        [VERIFIED_BINARY],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled C++ program exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    assert os.path.isfile(JSON_PATH), "The executed C++ program did not create movement_summary.json."
    with open(JSON_PATH, "r") as f:
        data = json.load(f)

    assert set(data.keys()) == {"matched_drones", "average_distance", "max_distance_id"}
    assert data["matched_drones"] == len(expected_distances)
    expected_average = round(sum(expected_distances.values()) / len(expected_distances), 2)
    assert isinstance(data["average_distance"], (int, float)) and not isinstance(data["average_distance"], bool)
    assert math.isclose(float(data["average_distance"]), expected_average, abs_tol=1e-9)
    expected_max_id = max(expected_distances, key=expected_distances.get)
    assert data["max_distance_id"] == expected_max_id

    assert os.path.isfile(LOG_PATH), "The executed C++ program did not create pipeline.log."
    with open(LOG_PATH, "r") as f:
        actual_lines = f.read().splitlines()
    expected_lines = [
        f"[INFO] Read {len(t1_rows)} records from t1",
        f"[INFO] Read {len(t2_rows)} records from t2",
        f"[INFO] Computed distances for {len(expected_distances)} drones",
        "[INFO] Results written to JSON",
    ]
    assert actual_lines == expected_lines


def test_cpp_program_compiles_and_handles_unseen_inputs():
    assert os.path.isfile(SOURCE_PATH), f"C++ source file {SOURCE_PATH} does not exist."
    assert not os.path.islink(SOURCE_PATH), f"C++ source file {SOURCE_PATH} must be a regular file, not a symlink."

    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-o", VERIFIED_BINARY],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE_PATH}. stdout={compile_result.stdout!r}, "
        f"stderr={compile_result.stderr!r}"
    )

    saved = {}
    for path in (T1_PATH, T2_PATH, JSON_PATH, LOG_PATH):
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()
        else:
            saved[path] = None

    try:
        ids = ["V_" + uuid.uuid4().hex for _ in range(7)]
        base = secrets.randbelow(500) + 20
        distances = [3, 8, 13]
        random.SystemRandom().shuffle(distances)

        t1 = [
            (ids[0], base, 1, 2),
            (ids[1], -5, base + 2, 7),
            (ids[2], 4, 9, base + 4),
            (ids[3], 99, 98, 97),
        ]
        t2 = [
            (ids[0], base + distances[0], 1, 2),
            (ids[1], -5, base + 2 + distances[1], 7),
            (ids[2], 4, 9, base + 4 + distances[2]),
            (ids[4], 6, 5, 4),
            (ids[5], 3, 2, 1),
        ]
        random.SystemRandom().shuffle(t1)
        random.SystemRandom().shuffle(t2)
        _run_case(t1, t2, {ids[i]: distances[i] for i in range(3)})

        ids2 = ["W_" + uuid.uuid4().hex for _ in range(4)]
        offset = secrets.randbelow(700) - 350
        t1_second = [
            (ids2[0], offset, 0, 0),
            (ids2[1], 1, offset, 1),
            (ids2[2], 50, 50, 50),
        ]
        t2_second = [
            (ids2[1], 1, offset + 9, 1),
            (ids2[0], offset + 4, 0, 0),
            (ids2[3], -1, -2, -3),
        ]
        _run_case(t1_second, t2_second, {ids2[0]: 4, ids2[1]: 9})
    finally:
        for path, content in saved.items():
            if content is None:
                if os.path.lexists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
        if os.path.exists(VERIFIED_BINARY):
            os.remove(VERIFIED_BINARY)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
