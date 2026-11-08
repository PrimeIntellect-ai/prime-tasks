#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
import random
import subprocess
from collections import Counter

import pytest

AGENT_PATH = "/home/user/query_solver.sh"
CSV_PATH = "/app/network_topology.csv"
VIDEO_PATH = "/app/signal_log.mp4"


def load_active_edges():
    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-f", "lavfi",
            "-i", f"movie={VIDEO_PATH},signalstats",
            "-show_entries", "frame=pts_time:frame_tags=lavfi.signalstats.YAVG",
            "-of", "json",
        ],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert probe.returncode == 0, f"ffprobe signalstats failed:\n{probe.stderr}"

    frames = json.loads(probe.stdout).get("frames", [])
    yavg_by_second = {}
    for frame in frames:
        tags = frame.get("tags", {})
        if "pts_time" not in frame or "lavfi.signalstats.YAVG" not in tags:
            continue
        second = int(round(float(frame["pts_time"])))
        yavg_by_second[second] = float(tags["lavfi.signalstats.YAVG"])

    assert yavg_by_second, "No signalstats YAVG values were obtained from the video"

    active = []
    with open(CSV_PATH, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            timestamp = int(row["timestamp_sec"])
            if yavg_by_second.get(timestamp, float("-inf")) > 100:
                active.append((
                    timestamp,
                    int(row["source_node"]),
                    int(row["target_node"]),
                    int(row["latency_ms"]),
                ))
    return active


def expected_answers(active, queries):
    max_node = max(max(u, v) for _, u, v, _ in active)
    n = max_node + 1
    adjacency = [[] for _ in range(n)]
    for _, u, v, weight in active:
        adjacency[u].append((v, weight))
        adjacency[v].append((u, weight))

    answers = []
    for start, end in queries:
        if start < 0 or end < 0 or start >= n or end >= n:
            answers.append(-1)
            continue

        distances = [10**30] * n
        distances[start] = 0
        queue = [(0, start)]
        while queue:
            distance, node = heapq.heappop(queue)
            if distance != distances[node]:
                continue
            if node == end:
                break
            for neighbor, weight in adjacency[node]:
                candidate = distance + weight
                if candidate < distances[neighbor]:
                    distances[neighbor] = candidate
                    heapq.heappush(queue, (candidate, neighbor))
        answers.append(-1 if distances[end] == 10**30 else distances[end])
    return answers


def find_cpp_sources():
    sources = []
    for root, _, files in os.walk("/home/user"):
        for name in files:
            if name.endswith((".cpp", ".cc", ".cxx", ".C")):
                path = os.path.join(root, name)
                if os.path.isfile(path):
                    sources.append(path)
    return sources


def is_exact_filtered_artifact(path, expected_rows):
    try:
        if not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
            return False
        with open(path, newline="", errors="strict") as f:
            rows = list(csv.reader(f))
    except (OSError, UnicodeError, csv.Error):
        return False

    rows = [row for row in rows if any(field.strip() for field in row)]
    if rows and [field.strip() for field in rows[0]] == [
        "timestamp_sec", "source_node", "target_node", "latency_ms"
    ]:
        rows = rows[1:]

    parsed = []
    try:
        for row in rows:
            if len(row) != 4:
                return False
            parsed.append(tuple(int(field.strip()) for field in row))
    except ValueError:
        return False
    return Counter(parsed) == Counter(expected_rows)


def find_filtered_artifact(expected_rows):
    for base in ("/home/user", "/tmp"):
        for root, _, files in os.walk(base):
            for name in files:
                path = os.path.join(root, name)
                if path in (CSV_PATH, "/tmp/test_final_state.py"):
                    continue
                if is_exact_filtered_artifact(path, expected_rows):
                    return path
    return None


def test_fuzz_equivalence_and_required_artifacts():
    assert os.path.isfile(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"

    active = load_active_edges()
    assert active, "The independently derived active graph is unexpectedly empty"

    # Preserve the original 1000 seeded fuzz queries and add complete valid-node
    # coverage so that the test cannot pass by returning -1 for nearly everything.
    random.seed(42)
    queries = [(random.randint(0, 500), random.randint(0, 500)) for _ in range(1000)]
    max_node = max(max(u, v) for _, u, v, _ in active)
    queries.extend((u, v) for u in range(max_node + 1) for v in range(max_node + 1))
    queries.extend([(0, 500), (500, 0), (500, 500)])

    expected = expected_answers(active, queries)
    input_text = "".join(f"{u} {v}\n" for u, v in queries)

    try:
        agent_proc = subprocess.run(
            ["bash", AGENT_PATH],
            input=input_text,
            text=True,
            capture_output=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Agent program timed out. Ensure the C++ code is optimized for up to 10,000 queries.")

    assert agent_proc.returncode == 0, (
        f"Agent script failed with return code {agent_proc.returncode}.\n"
        f"Stderr:\n{agent_proc.stderr}"
    )

    raw_lines = agent_proc.stdout.splitlines()
    assert len(raw_lines) == len(expected), (
        f"Output length mismatch: expected {len(expected)} lines, got {len(raw_lines)} lines."
    )
    for index, (line, answer) in enumerate(zip(raw_lines, expected)):
        assert line == str(answer), (
            f"Mismatch on query {index + 1} (Input: '{queries[index][0]} {queries[index][1]}'):\n"
            f"Expected: {answer}\nGot: {line!r}"
        )

    sources = find_cpp_sources()
    assert sources, "No C++ implementation (.cpp/.cc/.cxx) was found under /home/user"
    assert any(os.path.getsize(path) > 0 for path in sources), "The C++ source file is empty"

    artifact = find_filtered_artifact(active)
    assert artifact is not None, (
        "No preprocessing artifact containing exactly the video-active CSV edges was found "
        "under /home/user or /tmp"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
