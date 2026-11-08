#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import shutil
import subprocess
from collections import Counter

import cv2
import pytest

HOME = "/home/user"
CPP_PATH = os.path.join(HOME, "aggregate.cpp")
EDGES_PATH = os.path.join(HOME, "edges.csv")
STATS_PATH = os.path.join(HOME, "node_stats.csv")
VIDEO_PATH = "/app/graph_evolution.mp4"
BINARY_PATH = "/tmp/aggregate_verified"


def expected_from_video():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open {VIDEO_PATH}"

    edges = []
    frame_index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        assert frame.shape[0] == 100 and frame.shape[1] == 100, \
            f"Frame {frame_index} has unexpected dimensions {frame.shape[:2]}"
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        for source in range(10):
            for target in range(10):
                block = gray[source * 10:(source + 1) * 10,
                             target * 10:(target + 1) * 10]
                if float(block.mean()) < 128.0:
                    edges.append((frame_index, source, target))
        frame_index += 1

    cap.release()
    assert frame_index == 10, f"Expected 10 video frames, found {frame_index}"

    stats = []
    for node in range(10):
        out_weight = sum(1 for _, source, _ in edges if source == node)
        in_weight = sum(1 for _, _, target in edges if target == node)
        stats.append((node, out_weight, in_weight))
    return edges, stats


def read_edges(path):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, f"{path} is empty"
    assert rows[0] == ["frame_index", "source", "target"], \
        f"Incorrect edges.csv schema: {rows[0]}"

    parsed = []
    for line_number, row in enumerate(rows[1:], 2):
        assert len(row) == 3, f"Row {line_number} of edges.csv must have exactly 3 fields"
        try:
            values = tuple(int(value) for value in row)
        except ValueError:
            pytest.fail(f"Row {line_number} of edges.csv contains a non-integer value")
        parsed.append(values)
    return parsed


def read_stats(path):
    assert os.path.exists(path), f"Agent output file {path} missing."
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, f"{path} is empty"
    assert rows[0] == ["node", "total_out_weight", "total_in_weight"], \
        f"Incorrect node_stats.csv schema: {rows[0]}"
    assert len(rows[1:]) == 10, f"Expected exactly 10 data rows in {path}, got {len(rows[1:])}"

    parsed = []
    for line_number, row in enumerate(rows[1:], 2):
        assert len(row) == 3, f"Row {line_number} of node_stats.csv must have exactly 3 fields"
        try:
            parsed.append(tuple(int(value) for value in row))
        except ValueError:
            pytest.fail(f"Row {line_number} of node_stats.csv contains a non-integer value")
    assert [row[0] for row in parsed] == list(range(10)), \
        "node_stats.csv must contain nodes 0 through 9 sorted in ascending order"
    return parsed


def run_binary(expect_success=True):
    result = subprocess.run(
        [BINARY_PATH], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    if expect_success:
        assert result.returncode == 0, \
            f"aggregate program failed with exit code {result.returncode}: {result.stderr}"
    return result


def test_cpp_file_exists():
    assert os.path.isfile(CPP_PATH), \
        f"C++ source file {CPP_PATH} missing. You must write the aggregation logic in C++."


def test_edges_cpp_pipeline_and_node_stats():
    assert os.path.isfile(EDGES_PATH), f"Intermediate CSV {EDGES_PATH} missing."
    expected_edges, expected_stats = expected_from_video()
    submitted_edges = read_edges(EDGES_PATH)
    assert Counter(submitted_edges) == Counter(expected_edges), \
        "edges.csv does not contain exactly the edges encoded in all video frames"

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", BINARY_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f"aggregate.cpp failed to compile: {compile_result.stderr}"

    run_binary()
    assert read_stats(STATS_PATH) == expected_stats, \
        "node_stats.csv does not perfectly match the graph encoded in the video"

    original_edges = open(EDGES_PATH, "rb").read()
    try:
        synthetic = (
            "frame_index,source,target\n"
            "0,0,1\n"
            "1,0,1\n"
            "2,2,0\n"
            "3,9,9\n"
        )
        with open(EDGES_PATH, "w", newline="") as f:
            f.write(synthetic)
        if os.path.exists(STATS_PATH):
            os.remove(STATS_PATH)
        run_binary()
        synthetic_expected = [
            (0, 2, 1), (1, 0, 2), (2, 1, 0), (3, 0, 0), (4, 0, 0),
            (5, 0, 0), (6, 0, 0), (7, 0, 0), (8, 0, 0), (9, 1, 1)
        ]
        assert read_stats(STATS_PATH) == synthetic_expected, \
            "aggregate.cpp did not aggregate a controlled edges.csv correctly"

        with open(EDGES_PATH, "w", newline="") as f:
            f.write("wrong,source,target\n0,0,1\n")
        if os.path.exists(STATS_PATH):
            os.remove(STATS_PATH)
        malformed_result = run_binary(expect_success=False)
        assert malformed_result.returncode != 0, \
            "aggregate.cpp accepted edges.csv with an invalid schema"
    finally:
        with open(EDGES_PATH, "wb") as f:
            f.write(original_edges)

    run_binary()
    assert read_stats(STATS_PATH) == expected_stats, \
        "Final node_stats.csv was not correctly regenerated from the submitted edges.csv"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
