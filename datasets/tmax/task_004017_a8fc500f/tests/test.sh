#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import secrets
import sqlite3
import stat
import subprocess
import time

from PIL import Image, ImageDraw, ImageFont

SCRIPT_PATH = "/home/user/plan_restore.sh"
DB_PATH = "/home/user/backups.db"
IMAGE_PATH = "/app/network_latencies.png"
NODES = ["NodeA", "NodeB", "NodeC", "NodeD", "NodeE", "NodeF"]
TOPOLOGY = [
    ("NodeA", "NodeB"),
    ("NodeA", "NodeC"),
    ("NodeB", "NodeD"),
    ("NodeC", "NodeD"),
    ("NodeD", "NodeE"),
    ("NodeE", "NodeF"),
    ("NodeC", "NodeF"),
]


def run_script(target):
    start = time.monotonic()
    try:
        result = subprocess.run(
            ["bash", SCRIPT_PATH, target],
            capture_output=True,
            text=True,
            timeout=5.0,
        )
    except subprocess.TimeoutExpired:
        assert False, "The script execution timed out (exceeded 5.0 seconds)."
    elapsed = time.monotonic() - start
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. "
        f"Stderr: {result.stderr.strip()}"
    )
    assert elapsed < 1.0, (
        f"Script execution took {elapsed:.3f} seconds, which exceeds the "
        "1.0 second limit. Did you forget to index the database?"
    )
    return result.stdout.strip()


def shortest_path(edges, source, target):
    graph = {node: [] for node in NODES}
    for left, weight, right in edges:
        graph[left].append((right, weight))
        graph[right].append((left, weight))

    distances = {source: 0}
    queue = [(0, source)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == target:
            return distance
        for neighbor, weight in graph[node]:
            candidate = distance + weight
            if candidate < distances.get(neighbor, float("inf")):
                distances[neighbor] = candidate
                heapq.heappush(queue, (candidate, neighbor))
    raise AssertionError(f"No path from {source} to {target}")


def write_graph_image(edges):
    text = "\n".join(f"{left} {weight} {right}" for left, weight, right in edges)
    image = Image.new("RGB", (400, 300), color="white")
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 20
        )
    except OSError:
        font = ImageFont.load_default()
    draw.text((20, 20), text, fill=(0, 0, 0), font=font)
    image.save(IMAGE_PATH)


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert stat.S_ISREG(st.st_mode), f"The script {SCRIPT_PATH} is not a regular file."
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {SCRIPT_PATH} is not executable."


def test_script_execution_and_output():
    output = run_script("NodeF")
    assert output == "65", f"Expected output '65', but got '{output}'."


def test_latest_full_backup_query_is_indexed_and_fast():
    conn = sqlite3.connect(DB_PATH)
    try:
        plan_rows = conn.execute(
            "EXPLAIN QUERY PLAN SELECT node FROM backup_catalog "
            "WHERE is_full = 1 ORDER BY timestamp DESC LIMIT 1"
        ).fetchall()
        plan = " ".join(str(row[3]).upper() for row in plan_rows)
        assert "INDEX" in plan, f"Latest-full-backup query does not use an index: {plan}"
        assert "TEMP B-TREE" not in plan, (
            f"Index does not support the timestamp ordering efficiently: {plan}"
        )

        start = time.monotonic()
        row = conn.execute(
            "SELECT node FROM backup_catalog WHERE is_full = 1 "
            "ORDER BY timestamp DESC LIMIT 1"
        ).fetchone()
        elapsed = time.monotonic() - start
        assert row is not None
        assert elapsed < 0.100, (
            f"Latest-full-backup query took {elapsed:.3f} seconds, exceeding 100 ms."
        )
    finally:
        conn.close()


def test_dynamic_database_sources_targets_and_ocr_graph():
    original_image = open(IMAGE_PATH, "rb").read()
    weights = [10 + secrets.randbelow(50) for _ in TOPOLOGY]
    edges = [
        (left, weight, right)
        for (left, right), weight in zip(TOPOLOGY, weights)
    ]

    try:
        # Replace the diagram with another diagram in the exact same documented
        # format so fixed graph answers cannot satisfy the behavioral checks.
        write_graph_image(edges)

        targets = list(NODES)
        secrets.SystemRandom().shuffle(targets)
        conn = sqlite3.connect(DB_PATH)
        try:
            next_timestamp = conn.execute(
                "SELECT COALESCE(MAX(timestamp), 0) + 1 FROM backup_catalog"
            ).fetchone()[0]

            for target in targets:
                possible_sources = [node for node in NODES if node != target]
                source = secrets.choice(possible_sources)
                conn.execute(
                    "INSERT INTO backup_catalog "
                    "(node, timestamp, is_full, size_bytes) VALUES (?, ?, 1, ?)",
                    (source, next_timestamp, 5000000),
                )
                conn.commit()
                next_timestamp += 1

                expected = str(shortest_path(edges, source, target))
                output = run_script(target)
                assert output == expected, (
                    f"For latest full-backup node {source} and target {target}, "
                    f"expected '{expected}', but got '{output}'."
                )
        finally:
            conn.close()
    finally:
        with open(IMAGE_PATH, "wb") as image_file:
            image_file.write(original_image)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
