#!/bin/bash
set -e
mkdir -p /logs/verifier

VIDEO_BACKUP="/tmp/robot_tracking.mp4.orig.$$"
DB_BACKUP="/tmp/warehouse.db.orig.$$"
cp /app/robot_tracking.mp4 "$VIDEO_BACKUP"
cp /app/warehouse.db "$DB_BACKUP"
restore_artifacts() {
    cp "$VIDEO_BACKUP" /app/robot_tracking.mp4
    cp "$DB_BACKUP" /app/warehouse.db
    rm -f "$VIDEO_BACKUP" "$DB_BACKUP"
}
trap restore_artifacts EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import secrets
import sqlite3
import subprocess

import cv2
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/pipeline.py"
VIDEO_PATH = "/app/robot_tracking.mp4"
DB_PATH = "/app/warehouse.db"


def run_pipeline():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"

    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The script took longer than 300 seconds to execute.")

    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    )

    stdout_str = result.stdout.strip()
    try:
        return float(stdout_str)
    except ValueError:
        pytest.fail(
            f"Script output could not be parsed as a float. Output was: {stdout_str!r}"
        )


def write_video(sequence):
    out = cv2.VideoWriter(
        VIDEO_PATH, cv2.VideoWriter_fourcc(*"mp4v"), 1, (640, 480)
    )
    assert out.isOpened(), "Could not create generated verification video"
    for waypoint in sequence:
        for _ in range(5):
            frame = np.ones((480, 640, 3), dtype=np.uint8) * 255
            text = str(waypoint)
            font = cv2.FONT_HERSHEY_SIMPLEX
            font_scale = 10
            thickness = 15
            text_size = cv2.getTextSize(text, font, font_scale, thickness)[0]
            text_x = (640 - text_size[0]) // 2
            text_y = (480 + text_size[1]) // 2
            cv2.putText(
                frame,
                text,
                (text_x, text_y),
                font,
                font_scale,
                (0, 0, 0),
                thickness,
                cv2.LINE_AA,
            )
            out.write(frame)
    out.release()


def shortest_distance(nodes, edges, start, destination):
    graph = {node: [] for node in nodes}
    for source, target, weight in edges:
        graph[source].append((target, weight))
        graph[target].append((source, weight))

    distances = {start: 0.0}
    queue = [(0.0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == destination:
            return distance
        for neighbor, weight in graph[node]:
            candidate = distance + weight
            if candidate < distances.get(neighbor, float("inf")):
                distances[neighbor] = candidate
                heapq.heappush(queue, (candidate, neighbor))
    raise AssertionError("Generated destination is unreachable")


def make_generated_case(case_number):
    rng = random.Random(secrets.randbits(128))
    candidates = [12, 18, 24, 31, 45, 52, 63, 69, 82, 92]
    sequence = rng.sample(candidates, 5)

    # Build a dense graph so the database alone does not reveal the visited order.
    # Consecutive video waypoints have moderately weighted edges; all unrelated
    # edges are heavier. The direct start-to-finish edge controls the optimum and
    # differs substantially between the two generated cases.
    route_weights = [float(rng.randint(30, 40)) for _ in range(4)]
    direct_weight = float(rng.randint(14, 20) if case_number == 0 else rng.randint(80, 88))

    special = {}
    for index in range(4):
        a, b = sequence[index], sequence[index + 1]
        special[frozenset((a, b))] = (a, b, route_weights[index])
    special[frozenset((sequence[0], sequence[-1]))] = (
        sequence[0], sequence[-1], direct_weight
    )

    edges = []
    for i, first in enumerate(sequence):
        for second in sequence[i + 1:]:
            key = frozenset((first, second))
            if key in special:
                edges.append(special[key])
            else:
                source, target = (first, second) if rng.choice([True, False]) else (second, first)
                edges.append((source, target, float(rng.randint(100, 130))))

    db_edges = list(edges)
    db_nodes = [(node, f"Node_{node}") for node in sequence]
    rng.shuffle(db_edges)
    rng.shuffle(db_nodes)

    write_video(sequence)
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    connection = sqlite3.connect(DB_PATH)
    cursor = connection.cursor()
    cursor.execute("CREATE TABLE nodes (id INTEGER, label TEXT)")
    cursor.execute(
        "CREATE TABLE edges (source_id INTEGER, target_id INTEGER, weight REAL)"
    )
    cursor.executemany("INSERT INTO nodes VALUES (?, ?)", db_nodes)
    cursor.executemany("INSERT INTO edges VALUES (?, ?, ?)", db_edges)
    connection.commit()
    connection.close()

    edge_weights = {
        frozenset((source, target)): weight for source, target, weight in edges
    }
    actual_distance = sum(
        edge_weights[frozenset((sequence[i], sequence[i + 1]))]
        for i in range(len(sequence) - 1)
    )
    optimal_distance = shortest_distance(
        sequence, edges, sequence[0], sequence[-1]
    )
    return optimal_distance / actual_distance


def assert_close(agent_value, expected_value):
    error = abs(agent_value - expected_value)
    assert error <= 0.05, (
        f"Output {agent_value} is not within 0.05 of expected value "
        f"{expected_value:.5f} (Error: {error:.5f})"
    )


def test_pipeline_output_and_behavior():
    # Preserve the original verifier assertion on the supplied artifacts.
    actual_distance = 145.5
    shortest_distance = 82.0
    expected_value = shortest_distance / actual_distance
    assert_close(run_pipeline(), expected_value)

    # Exercise the ETL against fresh videos and databases. Expected answers are
    # derived from the generated waypoint sequence and graph rather than fixed.
    for case_number in range(2):
        generated_expected = make_generated_case(case_number)
        assert_close(run_pipeline(), generated_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
