#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import struct
import subprocess

import pytest

CJSON_DIR = "/app/cJSON"
SO_PATH = "/app/cJSON/libcjson.so"
SOURCE_PATH = "/home/user/process_sensors.c"
DATA_PATH = "/home/user/sensor_data.json"
RESULTS_PATH = "/home/user/results.csv"
BINARY_PATH = "/tmp/process_sensors_verifier"


def run(cmd, **kwargs):
    return subprocess.run(
        cmd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        **kwargs,
    )


def parse_results(path, require_two_decimals=False):
    assert os.path.isfile(path), f"Results file not found at {path}."
    actual = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            assert len(parts) == 2, (
                f"Invalid line format in {path}: '{line}'. "
                "Expected 'id,subtree_sum'."
            )
            node_id, value = parts
            assert node_id not in actual, f"Duplicate node id in results: {node_id}"
            if require_two_decimals:
                assert re.fullmatch(r"-?(?:0|[1-9][0-9]*)\.[0-9]{2}", value), (
                    f"Subtree sum is not formatted to exactly 2 decimal places: '{value}'"
                )
            try:
                actual[node_id] = float(value)
            except ValueError:
                pytest.fail(f"Invalid numeric value in {path}: '{value}'.")
    return actual


def expected_results(root):
    selected = {}

    def visit(node):
        total = float(node["value"])
        for child in node["children"]:
            total += visit(child)
        if total > 100.0:
            selected[node["id"]] = total
        return total

    visit(root)
    return selected


def assert_results_equal(actual, expected):
    assert set(actual) == set(expected), (
        f"Wrong result ids. Expected {set(expected)}, got {set(actual)}"
    )
    for node_id, value in expected.items():
        assert abs(actual[node_id] - value) < 0.0051, (
            f"Wrong subtree sum for {node_id}: expected {value:.2f}, "
            f"got {actual[node_id]:.2f}"
        )


def test_cjson_shared_library_built():
    """Verify make builds a genuine loadable cJSON shared library."""
    run(["make", "clean"], cwd=CJSON_DIR)
    run(["make"], cwd=CJSON_DIR)
    assert os.path.isfile(SO_PATH), (
        f"Shared library not found at {SO_PATH}. Did you fix the Makefile and run make?"
    )

    with open(SO_PATH, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", "libcjson.so is not an ELF binary"
    assert len(header) >= 18, "libcjson.so has a truncated ELF header"
    endian = "<" if header[5] == 1 else ">" if header[5] == 2 else None
    assert endian is not None, "libcjson.so has an invalid ELF byte order"
    assert struct.unpack(endian + "H", header[16:18])[0] == 3, (
        "libcjson.so is not an ELF shared object"
    )
    library = ctypes.CDLL(SO_PATH)
    assert getattr(library, "cJSON_Parse", None) is not None, (
        "libcjson.so does not export cJSON_Parse"
    )


def test_results_csv_accuracy():
    """Preserve the original assertion on the submitted results file."""
    expected = {
        "node3": 150.0,
        "node2": 155.0,
        "root": 215.5,
    }
    actual = parse_results(RESULTS_PATH)

    correct = 0
    for key, value in expected.items():
        if key in actual and abs(actual[key] - value) < 0.01:
            correct += 1
    accuracy = correct / max(len(expected), len(actual))
    assert accuracy >= 1.0, (
        f"Accuracy metric failed. Expected 1.0, got {accuracy}. "
        f"Expected dict: {expected}, Actual dict: {actual}"
    )


def test_program_builds_links_and_handles_derived_inputs():
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}."
    run([
        "gcc", "-std=c11", "-Wall", "-Wextra",
        "-I", CJSON_DIR,
        SOURCE_PATH,
        "-L", CJSON_DIR,
        "-Wl,-rpath," + CJSON_DIR,
        "-lcjson", "-lm",
        "-o", BINARY_PATH,
    ])

    dynamic_info = run(["readelf", "-d", BINARY_PATH]).stdout.lower()
    assert "libcjson.so" in dynamic_info, (
        "process_sensors.c was not linked against the cJSON shared library"
    )

    cases = [
        {
            "id": "verify_root_alpha",
            "value": 1.25,
            "children": [
                {
                    "id": "verify_branch_alpha",
                    "value": 60.0,
                    "children": [
                        {"id": "verify_leaf_alpha", "value": 45.0, "children": []}
                    ],
                },
                {
                    "id": "verify_branch_beta",
                    "value": -10.0,
                    "children": [
                        {"id": "verify_leaf_beta", "value": 200.0, "children": []},
                        {"id": "verify_leaf_gamma", "value": -100.0, "children": []},
                    ],
                },
            ],
        },
        {
            "id": "verify_root_delta",
            "value": -50.0,
            "children": [
                {
                    "id": "verify_exact_threshold",
                    "value": 75.0,
                    "children": [
                        {"id": "verify_twenty_five", "value": 25.0, "children": []}
                    ],
                },
                {
                    "id": "verify_over_threshold",
                    "value": 40.01,
                    "children": [
                        {"id": "verify_sixty", "value": 60.0, "children": []}
                    ],
                },
                {"id": "verify_large_leaf", "value": 125.5, "children": []},
            ],
        },
    ]

    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_results = None
    if os.path.exists(RESULTS_PATH):
        with open(RESULTS_PATH, "rb") as f:
            original_results = f.read()

    try:
        for case in cases:
            with open(DATA_PATH, "w", encoding="utf-8") as f:
                json.dump(case, f)
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
            env = os.environ.copy()
            env["LD_LIBRARY_PATH"] = CJSON_DIR + ":" + env.get("LD_LIBRARY_PATH", "")
            run([BINARY_PATH], cwd="/home/user", env=env)
            actual = parse_results(RESULTS_PATH, require_two_decimals=True)
            assert_results_equal(actual, expected_results(case))
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if original_results is None:
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
        else:
            with open(RESULTS_PATH, "wb") as f:
                f.write(original_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
