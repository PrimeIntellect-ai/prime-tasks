#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import stat
import subprocess
from collections import deque

import pytest

SCRIPT_PATH = "/home/user/find_path.sh"
PAPERS_PATH = "/home/user/papers.csv"
CITATIONS_PATH = "/home/user/citations.csv"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_output_A_E():
    try:
        result = subprocess.run(
            [SCRIPT_PATH, "A", "E"],
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed with error: {e.stderr}")

    try:
        output_json = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Output is not valid JSON. Output was:\n{result.stdout}")

    expected_json = [
        {"step": 1, "id": "A", "title": "Paper A", "year": 2000},
        {"step": 2, "id": "B", "title": "Paper B", "year": 2001},
        {"step": 3, "id": "D", "title": "Paper D", "year": 2003},
        {"step": 4, "id": "E", "title": "Paper E", "year": 2004}
    ]

    assert output_json == expected_json, f"Output JSON for A -> E did not match expected.\nExpected: {expected_json}\nGot: {output_json}"


def test_script_output_A_F():
    try:
        result = subprocess.run(
            [SCRIPT_PATH, "A", "F"],
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed with error: {e.stderr}")

    try:
        output_json = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Output is not valid JSON. Output was:\n{result.stdout}")

    expected_json = [
        {"step": 1, "id": "A", "title": "Paper A", "year": 2000},
        {"step": 2, "id": "C", "title": "Paper C", "year": 2002},
        {"step": 3, "id": "F", "title": "Paper F", "year": 2005}
    ]

    assert output_json == expected_json, f"Output JSON for A -> F did not match expected.\nExpected: {expected_json}\nGot: {output_json}"


def test_requires_exactly_two_arguments():
    for args in ([], ["A"], ["A", "E", "extra"]):
        result = subprocess.run(
            [SCRIPT_PATH, *args], capture_output=True, text=True, timeout=10
        )
        assert result.returncode != 0, (
            f"Script must reject invocation with {len(args)} arguments; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )


def reference_shortest_path(start, end, edges):
    adjacency = {}
    for source, target in edges:
        adjacency.setdefault(source, set()).add(target)

    queue = deque([[start]])
    shortest_length = None
    candidates = []
    while queue:
        path = queue.popleft()
        distance = len(path) - 1
        if shortest_length is not None and distance > shortest_length:
            break
        node = path[-1]
        if node == end:
            shortest_length = distance
            candidates.append(path)
            continue
        for neighbor in sorted(adjacency.get(node, ())):
            if neighbor not in path:
                queue.append(path + [neighbor])

    assert candidates, f"Verifier generated no path from {start} to {end}"
    return min(candidates, key=lambda path: ",".join(path))


def test_runtime_generated_graph_and_metadata():
    with open(PAPERS_PATH, "rb") as f:
        original_papers = f.read()
    with open(CITATIONS_PATH, "rb") as f:
        original_citations = f.read()

    ids = ["N_" + secrets.token_hex(6) for _ in range(7)]
    start, left, right, shared, detour1, detour2, target = ids
    metadata = {
        node_id: {
            "title": f"Generated paper {index} {secrets.token_hex(3)}",
            "year": 1980 + index * 3,
        }
        for index, node_id in enumerate(ids)
    }

    edges = [
        (start, left),
        (start, right),
        (left, shared),
        (right, shared),
        (shared, target),
        (left, detour1),
        (right, detour1),
        (detour1, detour2),
        (detour2, target),
        (shared, start),
        (detour1, left),
    ]
    random.SystemRandom().shuffle(edges)

    try:
        with open(PAPERS_PATH, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "title", "year"])
            for node_id in reversed(ids):
                writer.writerow([
                    node_id,
                    metadata[node_id]["title"],
                    metadata[node_id]["year"],
                ])

        with open(CITATIONS_PATH, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["citer_id", "cited_id"])
            writer.writerows(edges)

        for query_start, query_end in [
            (start, target),
            (left, target),
            (right, target),
            (shared, target),
        ]:
            path = reference_shortest_path(query_start, query_end, edges)
            expected = [
                {
                    "step": index,
                    "id": node_id,
                    "title": metadata[node_id]["title"],
                    "year": metadata[node_id]["year"],
                }
                for index, node_id in enumerate(path, 1)
            ]

            result = subprocess.run(
                [SCRIPT_PATH, query_start, query_end],
                capture_output=True,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"Script failed for generated query {query_start} -> {query_end}: "
                f"{result.stderr}"
            )
            try:
                actual = json.loads(result.stdout)
            except json.JSONDecodeError as exc:
                pytest.fail(
                    f"Generated query produced invalid JSON: {exc}; "
                    f"stdout={result.stdout!r}"
                )
            assert actual == expected, (
                f"Wrong generated result for {query_start} -> {query_end}.\n"
                f"Expected: {expected}\nGot: {actual}"
            )
    finally:
        with open(PAPERS_PATH, "wb") as f:
            f.write(original_papers)
        with open(CITATIONS_PATH, "wb") as f:
            f.write(original_citations)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
