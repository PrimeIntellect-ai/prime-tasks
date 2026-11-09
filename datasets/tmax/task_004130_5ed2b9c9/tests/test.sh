#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import random
import re
import stat
import subprocess
import uuid

SOURCE = "/home/user/solve.cpp"
BINARY = "/home/user/solve"
NETWORK = "/home/user/network.csv"
OUTPUT = "/home/user/shortest_path.txt"

ORIGINAL_CSV = """source,target,latency,reliability_score,timestamp
S,A,5,0.9,90
S,A,10,0.5,110
S,A,15,0.85,120
S,B,20,0.9,100
A,C,10,0.9,100
B,C,10,0.9,100
C,T,15,0.9,100
B,T,50,0.9,100
A,T,40,0.7,100
A,T,30,0.85,110
A,B,2,0.9,100
A,B,2,0.1,130
"""


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=5
    )
    assert result.returncode == 0, (
        f"Program exited with status {result.returncode}. stderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing after execution."


def write_rows(rows):
    with open(NETWORK, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["source", "target", "latency", "reliability_score", "timestamp"])
        writer.writerows(rows)


def latest_valid_edges(rows):
    latest = {}
    for source, target, latency, reliability, timestamp in rows:
        key = (source, target)
        record = (int(timestamp), int(latency), float(reliability))
        if key not in latest or record[0] > latest[key][0]:
            latest[key] = record
    return {
        key: latency
        for key, (_timestamp, latency, reliability) in latest.items()
        if reliability >= 0.8
    }


def shortest_distance(edges):
    graph = {}
    for (source, target), latency in edges.items():
        graph.setdefault(source, []).append((target, latency))
    queue = [(0, "S")]
    distances = {"S": 0}
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        if node == "T":
            return distance
        for target, latency in graph.get(node, []):
            candidate = distance + latency
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                heapq.heappush(queue, (candidate, target))
    raise AssertionError("Verifier generated a graph without an S-to-T path")


def validate_generated_case(rows):
    write_rows(rows)
    run_program()

    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    match = re.fullmatch(r"Latency: (-?\d+)\nPath: ([^\n,]+(?:,[^\n,]+)*)", content)
    assert match, f"Output has the wrong format:\n{content}"

    claimed_latency = int(match.group(1))
    path = match.group(2).split(",")
    assert path[0] == "S" and path[-1] == "T", f"Path must run from S to T: {path}"

    edges = latest_valid_edges(rows)
    actual_latency = 0
    for source, target in zip(path, path[1:]):
        assert (source, target) in edges, (
            f"Path uses missing, stale, or unreliable edge {source}->{target}"
        )
        actual_latency += edges[(source, target)]

    expected_latency = shortest_distance(edges)
    assert claimed_latency == actual_latency, (
        f"Claimed latency {claimed_latency} does not equal path latency {actual_latency}"
    )
    assert actual_latency == expected_latency, (
        f"Path latency {actual_latency} is not shortest; expected {expected_latency}"
    )


def test_shortest_path_result():
    assert os.path.exists(SOURCE), f"Source file {SOURCE} is missing."
    mode = os.stat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"Source path {SOURCE} is not a regular file."
    assert os.path.getsize(SOURCE) > 0, f"Source file {SOURCE} is empty."

    compilation = subprocess.run(
        ["g++", "-O2", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compilation.returncode == 0, f"Compilation failed:\n{compilation.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        f"Compiled executable {BINARY} is missing or not executable."
    )

    # Preserve the original result assertion, but first obtain the result by
    # running the submitted program against the original dataset.
    with open(NETWORK, "w") as f:
        f.write(ORIGINAL_CSV)
    run_program()

    output_file = "/home/user/shortest_path.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    expected_content = "Latency: 40\nPath: S,A,C,T"

    with open(output_file, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"Content of {output_file} is incorrect. Expected:\n{expected_content}\nGot:\n{actual_content}"

    rng = random.SystemRandom()
    for _ in range(3):
        a = "N" + uuid.uuid4().hex[:8]
        b = "N" + uuid.uuid4().hex[:8]
        c = "N" + uuid.uuid4().hex[:8]
        down = "N" + uuid.uuid4().hex[:8]
        x, y, z = (rng.randint(7, 20) for _ in range(3))
        best = x + y + z
        rows = [
            # The newest S->a row must replace a tempting stale low latency.
            ("S", a, 1, 0.99, 100),
            ("S", a, x, 0.91, 300),
            (a, c, y, 0.80, 200),
            (c, "T", z, 0.96, 200),
            # A valid but strictly longer alternative.
            ("S", b, x + y, 0.92, 150),
            (b, "T", z + 5, 0.94, 150),
            # This apparent shortcut is down because its newest row is unreliable.
            ("S", down, 1, 0.99, 100),
            ("S", down, 1, 0.30, 400),
            (down, "T", 1, 0.99, 100),
            # Latest A->T is also down despite an older reliable row.
            (a, "T", 1, 0.95, 100),
            (a, "T", 1, 0.40, 500),
            ("S", "T", best + 10, 0.90, 100),
            # Reverse edges ensure direction is respected.
            (a, "S", 1, 0.99, 600),
            ("T", c, 1, 0.99, 600),
        ]
        rng.shuffle(rows)
        validate_generated_case(rows)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
