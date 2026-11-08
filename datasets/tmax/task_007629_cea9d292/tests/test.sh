#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import random
import re
import subprocess
import uuid


def test_analyze_script_exists():
    script_path = "/home/user/analyze.py"
    assert os.path.exists(script_path), f"The script {script_path} was not created."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_top_warehouses_csv_exists_and_correct():
    output_path = "/home/user/top_warehouses.csv"
    assert os.path.exists(output_path), f"The output file {output_path} was not created."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

    expected_content = """warehouse_id,urgency_score
WH-02,300.00
WH-05,250.00
WH-04,80.00"""

    with open(output_path, "r") as f:
        content = f.read().strip()

    content_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert content_lines == expected_lines, (
        f"The content of {output_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{content}"
    )


def _expected_rows(warehouses, routes):
    graph = {}
    for source, target, weight in routes:
        graph.setdefault(source, []).append((target, weight))

    distances = {"WH-01": 0}
    queue = [(0, "WH-01")]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        for target, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                heapq.heappush(queue, (candidate, target))

    scores = []
    for warehouse_id, capacity, current_stock in warehouses:
        if warehouse_id != "WH-01" and warehouse_id in distances:
            score = (capacity - current_stock) / distances[warehouse_id]
            scores.append((warehouse_id, score))
    scores.sort(key=lambda item: (-item[1], item[0]))
    return [[warehouse_id, f"{score:.2f}"] for warehouse_id, score in scores[:3]]


def test_script_executes_and_handles_unseen_inputs():
    warehouse_path = "/home/user/warehouses.csv"
    route_path = "/home/user/routes.csv"
    output_path = "/home/user/top_warehouses.csv"
    script_path = "/home/user/analyze.py"

    backups = {}
    for path in (warehouse_path, route_path, output_path):
        with open(path, "rb") as handle:
            backups[path] = handle.read()

    rng = random.SystemRandom()
    token = uuid.uuid4().hex[:10]
    a = f"WH-A-{token}"
    b = f"WH-B-{token}"
    c = f"WH-C-{token}"
    d = f"WH-D-{token}"
    e = f"WH-E-{token}"
    unreachable = f"WH-U-{token}"

    source_to_b = rng.randint(1, 3)
    b_to_a = rng.randint(1, 3)
    source_to_c = rng.randint(4, 7)
    c_to_d = rng.randint(1, 3)
    a_to_e = rng.randint(1, 3)
    distance_a = source_to_b + b_to_a
    distance_d = source_to_c + c_to_d
    distance_e = distance_a + a_to_e

    tie_score = rng.randint(90, 140)
    free_a = distance_a * rng.randint(280, 340) + rng.randint(1, distance_a - 1)
    free_c = source_to_c * rng.randint(180, 230) + rng.randint(1, source_to_c - 1)
    free_b = source_to_b * tie_score
    free_d = distance_d * tie_score
    free_e = distance_e * rng.randint(40, 70)

    free_space = {
        "WH-01": 500,
        a: free_a,
        b: free_b,
        c: free_c,
        d: free_d,
        e: free_e,
        unreachable: 100000,
    }
    warehouses = []
    for warehouse_id, free in free_space.items():
        stock = rng.randint(25, 250)
        warehouses.append((warehouse_id, free + stock, stock))

    routes = [
        ("WH-01", a, distance_a + rng.randint(4, 8)),
        ("WH-01", b, source_to_b),
        (b, a, b_to_a),
        ("WH-01", c, source_to_c),
        (c, d, c_to_d),
        ("WH-01", d, distance_d + rng.randint(4, 8)),
        (a, e, a_to_e),
        (unreachable, "WH-01", 1),
        (d, c, rng.randint(1, 3)),
    ]
    expected = [["warehouse_id", "urgency_score"]] + _expected_rows(warehouses, routes)

    try:
        with open(warehouse_path, "w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["warehouse_id", "capacity", "current_stock"])
            writer.writerows(warehouses)
        with open(route_path, "w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["source_id", "target_id", "transit_time_days"])
            writer.writerows(routes)
        os.unlink(output_path)

        result = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"analyze.py failed on valid unseen CSV inputs.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(output_path), "analyze.py did not create top_warehouses.csv"

        with open(output_path, newline="") as handle:
            actual = list(csv.reader(handle))
        assert actual == expected, f"Expected CSV rows {expected!r}, got {actual!r}"
        assert len(actual) == 4
        assert actual[0] == ["warehouse_id", "urgency_score"]
        assert all(re.fullmatch(r"-?\d+\.\d{2}", row[1]) for row in actual[1:]), (
            "Every urgency_score must contain exactly two decimal places"
        )
    finally:
        for path, data in backups.items():
            with open(path, "wb") as handle:
                handle.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
