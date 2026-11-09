#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import subprocess
import tempfile
import time
import uuid
from collections import defaultdict, deque

import pytest

SOURCE = "A100"
TARGET = "Z999"
RESULT_PATH = "/home/user/result.json"
REQUIRED_KEYS = {"source", "target", "hops", "bottleneck_capacity", "path"}


def test_fast_graph_exists():
    assert os.path.isfile("/home/user/fast_graph.c"), "The source file /home/user/fast_graph.c does not exist."
    assert os.path.isfile("/home/user/fast_graph"), "The compiled binary /home/user/fast_graph does not exist."
    assert os.access("/home/user/fast_graph", os.X_OK), "The binary /home/user/fast_graph is not executable."


def measure(cmd):
    start = time.time()
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    duration = time.time() - start
    return duration, res.stdout, res.returncode


def validate_schema(value):
    assert isinstance(value, dict), "Result JSON must be an object."
    assert set(value.keys()) == REQUIRED_KEYS, f"Result JSON keys must be exactly {sorted(REQUIRED_KEYS)}."
    assert value["source"] == SOURCE, f"Expected source {SOURCE}, got {value['source']!r}."
    assert value["target"] == TARGET, f"Expected target {TARGET}, got {value['target']!r}."
    assert isinstance(value["hops"], int) and not isinstance(value["hops"], bool), "hops must be an integer."
    assert isinstance(value["bottleneck_capacity"], int) and not isinstance(value["bottleneck_capacity"], bool), "bottleneck_capacity must be an integer."
    assert isinstance(value["path"], list) and all(isinstance(node, str) for node in value["path"]), "path must be an array of strings."


def oracle(rows):
    capacities = defaultdict(int)
    for row in rows:
        if row["operation_type"] == "DATA_TRANSFER" and row["status"] == "SUCCESS":
            capacities[(row["source_node"], row["target_node"])] += int(row["payload_size"])

    graph = defaultdict(list)
    for (src, dst), capacity in capacities.items():
        graph[src].append((dst, capacity))

    distance = {SOURCE: 0}
    queue = deque([SOURCE])
    while queue:
        node = queue.popleft()
        for nxt, _ in graph[node]:
            if nxt not in distance:
                distance[nxt] = distance[node] + 1
                queue.append(nxt)

    assert TARGET in distance, "Generated test graph unexpectedly has no path."
    best = {SOURCE: float("inf")}
    previous = {}
    for depth in range(distance[TARGET]):
        for node in [n for n, d in distance.items() if d == depth and n in best]:
            for nxt, capacity in graph[node]:
                if distance.get(nxt) != depth + 1:
                    continue
                candidate = min(best[node], capacity)
                if nxt not in best or candidate > best[nxt]:
                    best[nxt] = candidate
                    previous[nxt] = node

    path = [TARGET]
    while path[-1] != SOURCE:
        path.append(previous[path[-1]])
    path.reverse()
    return {
        "source": SOURCE,
        "target": TARGET,
        "hops": len(path) - 1,
        "bottleneck_capacity": int(best[TARGET]),
        "path": path,
    }


def write_csv(path, rows):
    fields = ["timestamp", "source_node", "target_node", "operation_type", "payload_size", "status"]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def make_row(timestamp, src, dst, operation, size, status):
    return {
        "timestamp": str(timestamp),
        "source_node": src,
        "target_node": dst,
        "operation_type": operation,
        "payload_size": str(size),
        "status": status,
    }


def test_speedup_and_correctness():
    csv_path = "/home/user/data/network_logs.csv"
    assert os.path.isfile(csv_path), f"{csv_path} does not exist."

    ref_cmd = ["/app/path_finder", csv_path, SOURCE, TARGET]
    agent_cmd = ["/home/user/fast_graph", csv_path, SOURCE, TARGET]

    ref_time, ref_out, ref_rc = measure(ref_cmd)
    assert ref_rc == 0, f"Reference binary failed with return code {ref_rc}"

    if os.path.exists(RESULT_PATH):
        os.unlink(RESULT_PATH)
    agent_time, agent_out, agent_rc = measure(agent_cmd)
    assert agent_rc == 0, f"Agent binary failed with return code {agent_rc}"
    assert os.path.isfile(RESULT_PATH), f"The result file {RESULT_PATH} was not created."

    try:
        ref_json = json.loads(ref_out)
    except json.JSONDecodeError:
        pytest.fail("Reference binary did not output valid JSON.")

    try:
        with open(RESULT_PATH, "r") as f:
            agent_json = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Agent output file {RESULT_PATH} does not contain valid JSON.")

    assert "path" in ref_json, "Reference JSON missing 'path' key."
    assert "path" in agent_json, "Agent JSON missing 'path' key."
    assert ref_json["path"] == agent_json["path"], f"Paths do not match. Expected {ref_json['path']}, got {agent_json['path']}."
    assert "hops" in agent_json, "Agent JSON missing 'hops' key."
    assert "bottleneck_capacity" in agent_json, "Agent JSON missing 'bottleneck_capacity' key."

    validate_schema(agent_json)
    assert agent_json == ref_json, f"Result does not exactly match the reference JSON: expected {ref_json}, got {agent_json}."

    if agent_time == 0:
        agent_time = 1e-9
    speedup = ref_time / agent_time
    assert speedup >= 10.0, f"Speedup {speedup:.2f}x is below the 10.0x threshold. (Ref: {ref_time:.4f}s, Agent: {agent_time:.4f}s)"


def test_runtime_csv_aggregation_and_traversal():
    rng = random.SystemRandom()
    for case in range(3):
        token = uuid.uuid4().hex[:12]
        a = f"AGG_{token}"
        b = f"ALT_{token}"
        c = f"LONG_{token}"
        d = f"LONG_END_{token}"
        base = rng.randint(2000, 9000)
        rows = [
            make_row(1, SOURCE, a, "DATA_TRANSFER", base // 2 + 10, "SUCCESS"),
            make_row(2, SOURCE, a, "DATA_TRANSFER", base // 2 + 50, "SUCCESS"),
            make_row(3, a, TARGET, "DATA_TRANSFER", base + 30, "SUCCESS"),
            make_row(4, SOURCE, b, "DATA_TRANSFER", base + 100, "SUCCESS"),
            make_row(5, b, TARGET, "DATA_TRANSFER", base + 20, "SUCCESS"),
            make_row(6, SOURCE, c, "DATA_TRANSFER", base + 10000, "SUCCESS"),
            make_row(7, c, d, "DATA_TRANSFER", base + 10000, "SUCCESS"),
            make_row(8, d, TARGET, "DATA_TRANSFER", base + 10000, "SUCCESS"),
            make_row(9, SOURCE, TARGET, "PING", base + 99999, "SUCCESS"),
            make_row(10, SOURCE, TARGET, "DATA_TRANSFER", base + 99999, "FAILED"),
            make_row(11, a, TARGET, "AUTH", base + 99999, "SUCCESS"),
        ]
        if case == 1:
            rows.append(make_row(12, SOURCE, TARGET, "DATA_TRANSFER", rng.randint(1, 50), "SUCCESS"))
        rng.shuffle(rows)
        expected = oracle(rows)

        csv_path = os.path.join(tempfile.gettempdir(), f"network_case_{token}.csv")
        write_csv(csv_path, rows)
        try:
            if os.path.exists(RESULT_PATH):
                os.unlink(RESULT_PATH)
            res = subprocess.run(
                ["/home/user/fast_graph", csv_path, SOURCE, TARGET],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert res.returncode == 0, f"fast_graph failed on generated CSV with return code {res.returncode}: {res.stderr}"
            assert os.path.isfile(RESULT_PATH), "fast_graph did not create result.json for a generated CSV."
            try:
                with open(RESULT_PATH, "r") as f:
                    actual = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("fast_graph wrote invalid JSON for a generated CSV.")
            validate_schema(actual)
            assert actual == expected, f"Incorrect result for generated CSV. Expected {expected}, got {actual}."
        finally:
            if os.path.exists(csv_path):
                os.unlink(csv_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
