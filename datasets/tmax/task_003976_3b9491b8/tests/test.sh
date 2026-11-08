#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import sqlite3
import stat
import subprocess

import pytest
from PIL import Image, ImageDraw

SCRIPT = '/home/user/find_backup_route.sh'
OUTPUT = '/home/user/best_route.txt'
TOPOLOGY = '/app/topology.png'
DATABASE = '/app/nodes.db'


def run_submission():
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [SCRIPT],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"find_backup_route.sh exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT), "The script did not create /home/user/best_route.txt."


def read_result():
    with open(OUTPUT, 'r') as f:
        lines = f.read().splitlines()
    assert len(lines) >= 2, "Output file must contain at least two lines."
    try:
        latency = int(lines[1].strip())
    except ValueError:
        pytest.fail(f"Second line must be an integer latency, got: '{lines[1].strip()}'")
    return lines[0].strip(), latency


@pytest.fixture(scope='session', autouse=True)
def execute_original_submission():
    assert os.path.exists(SCRIPT), "/home/user/find_backup_route.sh does not exist."
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), "find_backup_route.sh must be a regular file."
    assert os.access(SCRIPT, os.X_OK), "find_backup_route.sh is not executable."
    with open(SCRIPT, 'rb') as f:
        first_line = f.readline(256).decode('utf-8', errors='replace').strip()
    assert first_line.startswith('#!') and 'bash' in first_line.lower(), (
        "find_backup_route.sh must be an executable Bash script with a Bash shebang."
    )
    run_submission()


def test_best_route_file_exists():
    assert os.path.isfile('/home/user/best_route.txt'), "/home/user/best_route.txt does not exist."


def test_best_route_content():
    with open('/home/user/best_route.txt', 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) >= 2, "Output file must contain at least two lines."

    path = lines[0].strip()
    latency_str = lines[1].strip()

    try:
        latency = int(latency_str)
    except ValueError:
        pytest.fail(f"Second line must be an integer latency, got: '{latency_str}'")

    expected_latency = 60
    error = abs(latency - expected_latency)

    assert error <= 0, f"Calculated latency {latency} is incorrect. Expected {expected_latency}. Error: {error}"

    expected_path = "DB_PRIMARY,DB_B,DB_D,DB_ARCHIVE"
    assert path == expected_path, f"Path is incorrect. Expected '{expected_path}', got '{path}'"


def shortest_path(edges, free_space):
    eligible = {name for name, space in free_space.items() if space >= 500}
    eligible.update({'DB_PRIMARY', 'DB_ARCHIVE'})
    graph = {}
    for source, destination, latency in edges:
        graph.setdefault(source, []).append((destination, latency))

    queue = [(0, ('DB_PRIMARY',), 'DB_PRIMARY')]
    best = {}
    while queue:
        distance, path, node = heapq.heappop(queue)
        if node in best and best[node] <= distance:
            continue
        best[node] = distance
        if node == 'DB_ARCHIVE':
            return ','.join(path), distance
        for destination, latency in graph.get(node, []):
            if destination in eligible:
                heapq.heappush(queue, (distance + latency, path + (destination,), destination))
    raise AssertionError('Verifier generated a graph without a valid route')


def write_topology(edges):
    text = '\n'.join(
        f'{source} -> {destination} : {latency}'
        for source, destination, latency in edges
    )
    image = Image.new('RGB', (600, 400), color=(255, 255, 255))
    draw = ImageDraw.Draw(image)
    draw.text((10, 10), text, fill=(0, 0, 0))
    image.save(TOPOLOGY)


def write_node_stats(free_space):
    connection = sqlite3.connect(DATABASE)
    try:
        connection.execute('DELETE FROM node_stats')
        connection.executemany(
            'INSERT INTO node_stats (node_name, free_space_gb) VALUES (?, ?)',
            list(free_space.items()),
        )
        connection.commit()
    finally:
        connection.close()


def test_script_dynamically_uses_topology_and_database():
    original_topology = open(TOPOLOGY, 'rb').read()
    original_database = open(DATABASE, 'rb').read()
    rng = random.SystemRandom()

    edges = [
        ('DB_PRIMARY', 'DB_A', rng.randint(11, 29)),
        ('DB_A', 'DB_C', rng.randint(11, 29)),
        ('DB_C', 'DB_ARCHIVE', rng.randint(11, 29)),
        ('DB_PRIMARY', 'DB_B', rng.randint(31, 59)),
        ('DB_B', 'DB_D', rng.randint(31, 59)),
        ('DB_D', 'DB_ARCHIVE', rng.randint(31, 59)),
    ]

    storage_cases = [
        {
            'DB_PRIMARY': 2000, 'DB_A': 700, 'DB_B': 100,
            'DB_C': 800, 'DB_D': 100, 'DB_ARCHIVE': 10000,
        },
        {
            'DB_PRIMARY': 2000, 'DB_A': 100, 'DB_B': 900,
            'DB_C': 100, 'DB_D': 650, 'DB_ARCHIVE': 10000,
        },
    ]

    try:
        write_topology(edges)
        for free_space in storage_cases:
            write_node_stats(free_space)
            expected_path, expected_latency = shortest_path(edges, free_space)
            run_submission()
            actual_path, actual_latency = read_result()
            assert actual_path == expected_path, (
                f"Dynamic topology/storage case expected path {expected_path!r}, "
                f"got {actual_path!r}"
            )
            assert actual_latency == expected_latency, (
                f"Dynamic topology/storage case expected latency {expected_latency}, "
                f"got {actual_latency}"
            )
    finally:
        with open(TOPOLOGY, 'wb') as f:
            f.write(original_topology)
        with open(DATABASE, 'wb') as f:
            f.write(original_database)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
