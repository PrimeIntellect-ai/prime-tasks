#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import itertools
import json
import math
import os
import random
import secrets
import statistics
import subprocess
from collections import Counter, defaultdict
from datetime import datetime, timedelta

import pytest

SCRIPT = "/home/user/analyze_logs.py"
CSV_PATH = "/home/user/api_latency.csv"
OUTPUT_PATH = "/home/user/closest_ips.json"
START = datetime(2023, 10, 1, 10, 0, 0)


def load_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file is missing: {OUTPUT_PATH}"
    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} does not contain valid JSON.")


def assert_original_content():
    data = load_output()
    expected_keys = {"ip1", "ip2", "distance"}
    assert set(data.keys()) == expected_keys, \
        f"JSON keys must be exactly {expected_keys}, got {set(data.keys())}"
    assert data["ip1"] == "10.0.0.5", \
        f"Expected ip1 to be '10.0.0.5', got '{data['ip1']}'"
    assert data["ip2"] == "192.168.1.100", \
        f"Expected ip2 to be '192.168.1.100', got '{data['ip2']}'"
    distance = data["distance"]
    assert isinstance(distance, (int, float)), \
        f"Distance must be a number, got {type(distance)}"
    expected_distance = 0.3155
    tolerance = 0.005
    assert abs(distance - expected_distance) <= tolerance, \
        f"Distance {distance} is not within {tolerance} of expected {expected_distance}"


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, \
        f"analyze_logs.py failed with code {result.returncode}:\n{result.stderr}"


def oracle(rows):
    counts = Counter(row[1] for row in rows)
    valid = sorted(ip for ip, count in counts.items() if count >= 5)
    buckets = {ip: defaultdict(list) for ip in valid}

    for timestamp, ip, latency in rows:
        if ip not in buckets:
            continue
        dt = datetime.fromisoformat(timestamp)
        delta = (dt - START).total_seconds()
        if 0 <= delta < 600:
            buckets[ip][int(delta // 60)].append(float(latency))

    normalized = {}
    for ip in valid:
        values = []
        for minute in range(10):
            vals = buckets[ip].get(minute, [])
            values.append(sum(vals) / len(vals) if vals else None)

        available = [value for value in values if value is not None]
        assert available, f"Generated valid IP {ip} has no in-window observations"
        first = available[0]
        last = first
        for i, value in enumerate(values):
            if value is None:
                values[i] = last
            else:
                last = value

        mean = sum(values) / 10
        sd = statistics.stdev(values)
        if sd == 0:
            normalized[ip] = [0.0] * 10
        else:
            normalized[ip] = [(value - mean) / sd for value in values]

    candidates = []
    for ip1, ip2 in itertools.combinations(valid, 2):
        distance = math.sqrt(sum(
            (a - b) ** 2 for a, b in zip(normalized[ip1], normalized[ip2])
        ))
        candidates.append((distance, ip1, ip2))
    candidates.sort()
    assert len(candidates) >= 2
    return {
        "ip1": candidates[0][1],
        "ip2": candidates[0][2],
        "distance": round(candidates[0][0], 4),
    }, candidates


def make_case():
    rng = random.SystemRandom()
    while True:
        octet = secrets.randbelow(180) + 20
        ips = [f"10.{octet}.{i}.{secrets.randbelow(240) + 1}" for i in range(1, 7)]
        rng.shuffle(ips)
        ip_a, ip_b, ip_c, ip_d, ip_e, invalid_ip = ips

        anchors = {
            1: rng.uniform(45, 75),
            4: rng.uniform(90, 125),
            7: rng.uniform(55, 85),
            9: rng.uniform(105, 145),
        }
        expanded = []
        last = anchors[1]
        for minute in range(10):
            if minute in anchors:
                last = anchors[minute]
            expanded.append(last)

        rows = []
        # A has two observations per minute whose mean is the target value.
        for minute, target in enumerate(expanded):
            delta = rng.uniform(0.4, 2.0)
            rows.append(((START + timedelta(minutes=minute, seconds=5)).isoformat(), ip_a, target - delta))
            rows.append(((START + timedelta(minutes=minute, seconds=45)).isoformat(), ip_a, target + delta))

        # B has only four in-window entries and qualifies solely because of its
        # fifth raw entry outside the resampling window. Its gaps require both
        # leading back-fill and forward-fill.
        scale = rng.uniform(1.6, 2.5)
        offset = rng.uniform(30, 90)
        for minute in (1, 4, 7, 9):
            perturb = rng.uniform(0.35, 0.75) if minute == 7 else 0.0
            value = scale * anchors[minute] + offset + perturb
            rows.append(((START + timedelta(minutes=minute, seconds=20)).isoformat(), ip_b, value))
        rows.append(((START - timedelta(seconds=1)).isoformat(), ip_b, 9999.0))

        # Distinct valid profiles, including a zero-variance profile.
        for minute in range(10):
            rows.append(((START + timedelta(minutes=minute, seconds=10)).isoformat(), ip_c,
                         40.0 if minute % 2 == 0 else 180.0))
            rows.append(((START + timedelta(minutes=minute, seconds=30)).isoformat(), ip_d,
                         25.0 + minute * minute * 3.0))
        for minute in (0, 2, 4, 6, 8):
            rows.append(((START + timedelta(minutes=minute, seconds=15)).isoformat(), ip_e, 77.0))

        # This four-entry IP mimics A. Failing the quality gate would make it
        # an incorrect zero-distance winner.
        for minute in (1, 4, 7, 9):
            rows.append(((START + timedelta(minutes=minute, seconds=35)).isoformat(),
                         invalid_ip, anchors[minute]))

        rng.shuffle(rows)
        expected, distances = oracle(rows)
        # Regenerate in the unlikely event that random profiles are ambiguous.
        if distances[1][0] - distances[0][0] > 0.2 and {expected["ip1"], expected["ip2"]} == {ip_a, ip_b}:
            return rows, expected


def write_rows(rows):
    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "ip", "latency_ms"])
        writer.writerows(rows)


def assert_dynamic_output(expected):
    data = load_output()
    assert set(data.keys()) == {"ip1", "ip2", "distance"}
    assert data["ip1"] == expected["ip1"], \
        f"Expected dynamically derived ip1 {expected['ip1']}, got {data['ip1']}"
    assert data["ip2"] == expected["ip2"], \
        f"Expected dynamically derived ip2 {expected['ip2']}, got {data['ip2']}"
    assert isinstance(data["distance"], (int, float)) and not isinstance(data["distance"], bool)
    assert data["distance"] == expected["distance"], \
        f"Expected dynamically derived distance {expected['distance']}, got {data['distance']}"


def test_closest_ips_json_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file is missing: {OUTPUT_PATH}"


def test_closest_ips_json_content():
    assert_original_content()


def test_script_exists_and_reproduces_original_result():
    assert os.path.isfile(SCRIPT), f"Required script is missing: {SCRIPT}"
    assert os.path.getsize(SCRIPT) > 0, f"Required script is empty: {SCRIPT}"
    compile_result = subprocess.run(
        ["python3", "-m", "py_compile", SCRIPT], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert compile_result.returncode == 0, f"analyze_logs.py is not valid Python:\n{compile_result.stderr}"
    run_script()
    assert_original_content()


def test_script_processes_unseen_inputs_through_required_pipeline():
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    restore_result = None
    try:
        for _ in range(3):
            rows, expected = make_case()
            write_rows(rows)
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
            run_script()
            assert_dynamic_output(expected)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if os.path.isfile(SCRIPT):
            restore_result = subprocess.run(
                ["python3", SCRIPT], cwd="/home/user", text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
            )
        if restore_result is None or restore_result.returncode != 0:
            if original_output is not None:
                with open(OUTPUT_PATH, "wb") as f:
                    f.write(original_output)

    assert os.path.isfile(SCRIPT), "analyze_logs.py disappeared after execution"
    assert restore_result is not None and restore_result.returncode == 0, \
        f"analyze_logs.py failed when restoring the original result: {getattr(restore_result, 'stderr', '')}"
    assert_original_content()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
