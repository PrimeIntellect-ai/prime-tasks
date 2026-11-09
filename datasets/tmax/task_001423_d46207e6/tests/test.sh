#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess
import time

DIR_PATH = "/home/user/etl_pipeline"
MAKEFILE_PATH = os.path.join(DIR_PATH, "Makefile")
MATCH_PY_PATH = os.path.join(DIR_PATH, "match.py")
SOURCE_A_PATH = os.path.join(DIR_PATH, "source_A.csv")
SOURCE_B_JSON_PATH = os.path.join(DIR_PATH, "source_B.json")
SOURCE_B_NORM_PATH = os.path.join(DIR_PATH, "source_B_norm.csv")
MATCHES_PATH = os.path.join(DIR_PATH, "matches.csv")


def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) *
         math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def read_a():
    with open(SOURCE_A_PATH, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "lat", "lon"]
        return [(r["id"], float(r["lat"]), float(r["lon"])) for r in reader]


def read_b_json():
    with open(SOURCE_B_JSON_PATH, encoding="utf-8") as f:
        values = json.load(f)
    return [(v["loc_id"], float(v["coordinates"]["latitude"]),
             float(v["coordinates"]["longitude"])) for v in values]


def expected_matches(source_a, source_b):
    result = []
    for aid, alat, alon in source_a:
        for bid, blat, blon in source_b:
            distance = haversine(alat, alon, blat, blon)
            if distance <= 5.0:
                result.append((aid, bid, f"{distance:.2f}"))
    return sorted(result, key=lambda x: (x[0], x[1]))


def assert_normalized(expected_b):
    with open(SOURCE_B_NORM_PATH, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["id", "lat", "lon"], f"Bad normalized header: {rows[:1]}"
    assert len(rows) == len(expected_b) + 1, f"Expected every JSON record exactly once, got {rows[1:]}"
    actual = []
    for row in rows[1:]:
        assert len(row) == 3, f"Invalid normalized row: {row}"
        actual.append((row[0], float(row[1]), float(row[2])))
    assert actual == expected_b, f"Normalization does not reflect source_B.json: {actual} != {expected_b}"


def assert_matches(expected):
    with open(MATCHES_PATH, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["id_A", "id_B", "distance_km"], f"Bad matches header: {rows[:1]}"
    actual = []
    for row in rows[1:]:
        assert len(row) == 3, f"Invalid match row: {row}"
        # Require exactly two decimal places, not merely a numerically equal float.
        whole, dot, fractional = row[2].partition(".")
        assert dot == "." and len(fractional) == 2 and whole.lstrip("-").isdigit() and fractional.isdigit(), \
            f"Distance is not formatted to exactly 2 decimals: {row[2]}"
        actual.append(tuple(row))
    assert actual == expected, f"Matches mismatch. Expected {expected}, got {actual}"


def run_make_all_clean():
    for path in (SOURCE_B_NORM_PATH, MATCHES_PATH):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(["make", "all"], cwd=DIR_PATH, capture_output=True, text=True)
    assert result.returncode == 0, f"make all failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(SOURCE_B_NORM_PATH)
    assert os.path.isfile(MATCHES_PATH)


def test_files_and_pipeline_against_actual_sources():
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile not found at {MAKEFILE_PATH}"
    assert os.path.isfile(MATCH_PY_PATH), f"match.py not found at {MATCH_PY_PATH}"
    source_a = read_a()
    source_b = read_b_json()
    run_make_all_clean()
    assert_normalized(source_b)
    assert_matches(expected_matches(source_a, source_b))


def test_pipeline_generalizes_and_dag_dependencies_are_real():
    original_a = open(SOURCE_A_PATH, "rb").read()
    original_b = open(SOURCE_B_JSON_PATH, "rb").read()
    try:
        # Unpredictable IDs prevent a fixture-only emitter; points exercise inside,
        # outside, inclusive-boundary behavior, full Cartesian matching, and sorting.
        token = str((time.time_ns() ^ os.getpid()) % 1000000000)
        a_rows = [
            ("Z" + token, 0.0, 0.0),
            ("A" + token, 10.0, 10.0),
            ("M" + token, -20.0, 130.0),
        ]
        # Longitude delta giving exactly 5 km on the equator under R=6371.
        boundary_lon = math.degrees(5.0 / 6371.0)
        b_values = [
            {"loc_id": "Y" + token, "coordinates": {"latitude": 0.0, "longitude": boundary_lon}},
            {"loc_id": "B" + token, "coordinates": {"latitude": 10.01, "longitude": 10.01}},
            {"loc_id": "C" + token, "coordinates": {"latitude": 10.02, "longitude": 10.02}},
            {"loc_id": "X" + token, "coordinates": {"latitude": 50.0, "longitude": -40.0}},
        ]
        with open(SOURCE_A_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "lat", "lon"])
            writer.writerows(a_rows)
        with open(SOURCE_B_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(b_values, f)
            f.write("\n")

        run_make_all_clean()
        expected_b = [(v["loc_id"], float(v["coordinates"]["latitude"]),
                       float(v["coordinates"]["longitude"])) for v in b_values]
        assert_normalized(expected_b)
        assert_matches(expected_matches(a_rows, expected_b))

        # match.py must be an effective dependency and its recipe must execute it.
        os.remove(MATCHES_PATH)
        result = subprocess.run(["make", "match"], cwd=DIR_PATH, capture_output=True, text=True)
        assert result.returncode == 0 and os.path.isfile(MATCHES_PATH), result.stdout + result.stderr
        assert_matches(expected_matches(a_rows, expected_b))

        # Updating source A must rebuild matches through the declared dependency.
        a_rows.append(("D" + token, -20.005, 130.005))
        time.sleep(1.1)
        with open(SOURCE_A_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "lat", "lon"])
            writer.writerows(a_rows)
        result = subprocess.run(["make", "all"], cwd=DIR_PATH, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        assert_matches(expected_matches(a_rows, expected_b))

        # Updating JSON must run normalization and then matching.
        b_values.append({"loc_id": "D" + token, "coordinates": {"latitude": -20.006, "longitude": 130.006}})
        time.sleep(1.1)
        with open(SOURCE_B_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(b_values, f)
            f.write("\n")
        result = subprocess.run(["make", "all"], cwd=DIR_PATH, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        expected_b = [(v["loc_id"], float(v["coordinates"]["latitude"]),
                       float(v["coordinates"]["longitude"])) for v in b_values]
        assert_normalized(expected_b)
        assert_matches(expected_matches(a_rows, expected_b))
    finally:
        with open(SOURCE_A_PATH, "wb") as f:
            f.write(original_a)
        with open(SOURCE_B_JSON_PATH, "wb") as f:
            f.write(original_b)


def test_makefile_explicit_match_dependencies():
    # Preserve the original assertion that source_B.json changes trigger both DAG stages.
    run_make_all_clean()
    time.sleep(1.1)
    os.utime(SOURCE_B_JSON_PATH, None)
    result = subprocess.run(["make", "-n", "all"], cwd=DIR_PATH, capture_output=True, text=True)
    assert result.returncode == 0
    output = (result.stdout + result.stderr).lower()
    assert "source_b_norm" in output or "normalize" in output
    assert "match" in output or "matches.csv" in output

    # Verify each required match prerequisite causes matches.csv to be considered stale.
    for dependency in (SOURCE_A_PATH, SOURCE_B_NORM_PATH, MATCH_PY_PATH):
        run_make_all_clean()
        time.sleep(1.1)
        os.utime(dependency, None)
        result = subprocess.run(["make", "-n", "match"], cwd=DIR_PATH, capture_output=True, text=True)
        assert result.returncode == 0
        assert result.stdout.strip(), f"match does not declare {os.path.basename(dependency)} as a dependency"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
