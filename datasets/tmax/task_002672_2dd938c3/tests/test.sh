#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import random
import subprocess
import pytest

SOURCE = "/home/user/trajectory_analyzer.cpp"
EXECUTABLE = "/home/user/analyzer"
CSV_PATH = "/home/user/route.csv"
OUTPUT_PATH = "/home/user/fixed_analysis.json"


def compute_expected_distance(csv_path):
    def haversine(lat1, lon1, lat2, lon2):
        R = 6371.0
        dLat = (lat2 - lat1) * math.pi / 180.0
        dLon = (lon2 - lon1) * math.pi / 180.0
        a = math.sin(dLat / 2) ** 2 + math.cos(lat1 * math.pi / 180.0) * math.cos(lat2 * math.pi / 180.0) * math.sin(dLon / 2) ** 2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return R * c

    total_dist = 0.0
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        prev_lat = None
        prev_lon = None
        for row in reader:
            lat = float(row['latitude'])
            lon = float(row['longitude'])
            if prev_lat is not None and prev_lon is not None:
                total_dist += haversine(prev_lat, prev_lon, lat, lon)
            prev_lat = lat
            prev_lon = lon
    return total_dist


def read_and_check_output(expected_distance):
    assert os.path.isfile(OUTPUT_PATH), f"Expected output file {OUTPUT_PATH} to exist."
    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")

    assert "total_distance_km" in data, "JSON output missing 'total_distance_km' key."
    actual_distance = data["total_distance_km"]
    assert isinstance(actual_distance, (int, float)), "'total_distance_km' must be a number."
    assert math.isfinite(actual_distance), "'total_distance_km' must be finite."

    tolerance = 0.001
    diff = abs(expected_distance - actual_distance)
    assert diff <= tolerance, f"Expected total distance approx {expected_distance:.4f}, but got {actual_distance}. Difference {diff} exceeds tolerance {tolerance}."


def run_analyzer_and_check():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run([EXECUTABLE], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert result.returncode == 0, f"Analyzer exited with {result.returncode}: {result.stderr}"
    read_and_check_output(compute_expected_distance(CSV_PATH))


def write_route(points):
    with open(CSV_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'latitude', 'longitude'])
        for i, (lat, lon) in enumerate(points):
            writer.writerow([i, format(lat, '.15g'), format(lon, '.15g')])


def test_fixed_analysis_json_exists():
    path = OUTPUT_PATH
    assert os.path.isfile(path), f"Expected output file {path} to exist."


def test_fixed_analysis_json_content():
    path = OUTPUT_PATH
    assert os.path.isfile(path), f"Expected output file {path} to exist."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert "total_distance_km" in data, "JSON output missing 'total_distance_km' key."

    csv_path = CSV_PATH
    assert os.path.isfile(csv_path), f"Input data file {csv_path} is missing."

    expected_distance = compute_expected_distance(csv_path)
    actual_distance = data["total_distance_km"]

    assert isinstance(actual_distance, (int, float)), "'total_distance_km' must be a number."

    tolerance = 0.001
    diff = abs(expected_distance - actual_distance)
    assert diff <= tolerance, f"Expected total distance approx {expected_distance:.4f}, but got {actual_distance}. Difference {diff} exceeds tolerance {tolerance}."


def test_compiled_analyzer_on_derived_routes():
    assert os.path.isfile(SOURCE), f"Expected source file {SOURCE} to exist."
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK), "Compiled analyzer is missing or not executable."

    with open(CSV_PATH, 'rb') as f:
        original_route = f.read()

    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    try:
        # General nontrivial route: catches an incorrect longitude conversion.
        lat = rng.uniform(-55.0, 55.0)
        lon = rng.uniform(-140.0, 140.0)
        points = [(lat, lon)]
        for _ in range(1500):
            lat += rng.uniform(-0.004, 0.004)
            lon += rng.uniform(-0.004, 0.004)
            points.append((lat, lon))
        write_route(points)
        run_analyzer_and_check()

        # Sub-float-resolution oscillations: coordinate storage must retain double precision.
        lat = rng.uniform(30.0, 50.0)
        lon = rng.uniform(-110.0, -60.0)
        delta_lat = rng.uniform(0.7e-7, 1.3e-7)
        delta_lon = rng.uniform(0.7e-7, 1.3e-7)
        points = [(lat, lon) if i % 2 == 0 else (lat + delta_lat, lon + delta_lon) for i in range(20000)]
        write_route(points)
        run_analyzer_and_check()

        # Long repeated route: exposes single-precision distance accumulation.
        step = rng.uniform(0.0008, 0.0012)
        points = [(0.0, 0.0) if i % 2 == 0 else (0.0, step) for i in range(120000)]
        write_route(points)
        run_analyzer_and_check()
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_route)
        subprocess.run([EXECUTABLE], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
TEST_EOF

if rm -f /home/user/analyzer /home/user/fixed_analysis.json \
   && test -f /home/user/trajectory_analyzer.cpp \
   && g++ -std=c++17 /home/user/trajectory_analyzer.cpp -o /home/user/analyzer \
   && test -x /home/user/analyzer \
   && /home/user/analyzer \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
