#!/bin/bash
set -e
mkdir -p /logs/verifier

RAW_BACKUP=$(mktemp)
cp /home/user/raw_edges.json "$RAW_BACKUP"
RESULT_BACKUP=$(mktemp)
HAD_RESULT=0
if [ -f /home/user/result.txt ]; then
    cp /home/user/result.txt "$RESULT_BACKUP"
    HAD_RESULT=1
fi

cleanup() {
    cp "$RAW_BACKUP" /home/user/raw_edges.json
    if [ "$HAD_RESULT" -eq 1 ]; then
        cp "$RESULT_BACKUP" /home/user/result.txt
    else
        rm -f /home/user/result.txt
    fi
    rm -f "$RAW_BACKUP" "$RESULT_BACKUP" /tmp/analyze_submission
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
from collections import defaultdict

import pytest

SOURCE = "/home/user/analyze.cpp"
INPUT = "/home/user/raw_edges.json"
OUTPUT = "/home/user/result.txt"
BINARY = "/tmp/analyze_submission"


def get_expected_result():
    """Dynamically compute the expected result from the raw JSON file."""
    assert os.path.isfile(INPUT), f"File {INPUT} is missing."

    with open(INPUT, "r") as f:
        try:
            edges = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {INPUT} is not valid JSON.")

    graph = defaultdict(set)
    for edge in edges:
        src = edge.get("src")
        dst = edge.get("dst")
        if src is not None and dst is not None and src != dst:
            graph[src].add(dst)
            graph[dst].add(src)

    max_degree = -1
    max_node = -1
    for node, neighbors in graph.items():
        degree = len(neighbors)
        if degree > max_degree:
            max_degree = degree
            max_node = node
        elif degree == max_degree and node < max_node:
            max_node = node

    return f"Max Degree Node: {max_node}, Degree: {max_degree}"


def run_compiled_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    try:
        completed = subprocess.run(
            [BINARY], capture_output=True, text=True, timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The compiled analyze.cpp program timed out.")
    assert completed.returncode == 0, (
        "The compiled analyze.cpp program failed.\n"
        f"stdout: {completed.stdout}\n"
        f"stderr: {completed.stderr}"
    )
    assert os.path.isfile(OUTPUT), (
        f"The compiled program did not generate {OUTPUT}."
    )
    with open(OUTPUT, "r") as f:
        return f.read().strip()


def test_analyze_cpp_exists():
    """Check if the analyze.cpp file was created."""
    assert os.path.isfile(SOURCE), f"Required source file {SOURCE} is missing."


def test_result_txt_exists_and_correct():
    """Check if result.txt exists and contains the correct output."""
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not generated."

    expected_output = get_expected_result()
    with open(OUTPUT, "r") as f:
        content = f.read().strip()

    assert content == expected_output, (
        f"Incorrect content in {OUTPUT}.\n"
        f"Expected: '{expected_output}'\n"
        f"Got: '{content}'"
    )


def test_source_includes_provided_json_header():
    with open(SOURCE, "r") as f:
        source_text = f.read()
    assert re.search(r'^\s*#\s*include\s*"json\.hpp"', source_text, re.MULTILINE), (
        'analyze.cpp must include the provided header with #include "json.hpp".'
    )


def test_compile_and_run_on_original_input():
    completed = subprocess.run(
        ["g++", "-std=c++17", "-O3", SOURCE, "-o", BINARY],
        capture_output=True,
        text=True,
    )
    assert completed.returncode == 0, (
        "analyze.cpp did not compile with g++ -std=c++17.\n"
        f"stdout: {completed.stdout}\n"
        f"stderr: {completed.stderr}"
    )

    expected = get_expected_result()
    actual = run_compiled_program()
    assert actual == expected, (
        "The compiled program produced an incorrect result on raw_edges.json.\n"
        f"Expected: '{expected}'\nGot: '{actual}'"
    )


def test_compiled_program_on_generated_inputs():
    assert os.path.isfile(BINARY), "The verified binary was not compiled."
    rng = secrets.SystemRandom()
    ids = rng.sample(range(10000, 1000000), 40)

    # Unique-edge counting, reverse duplicates, repeated interactions, and loops.
    case1 = []
    center = ids[0]
    for leaf in ids[1:10]:
        case1.extend([
            {"src": center, "dst": leaf, "interaction_type": "like"},
            {"src": leaf, "dst": center, "interaction_type": "reply"},
            {"src": center, "dst": leaf, "interaction_type": "share"},
        ])
    other = ids[10]
    for leaf in ids[11:17]:
        case1.append({"src": other, "dst": leaf, "interaction_type": "like"})
    case1.append({"src": center, "dst": center, "interaction_type": "like"})

    # Two disjoint stars with equal degree exercise the numeric tie-break rule.
    low, high = sorted((ids[17], ids[18]))
    case2 = []
    for leaf in ids[19:24]:
        case2.append({"src": low, "dst": leaf, "interaction_type": "like"})
    for leaf in ids[24:29]:
        case2.append({"src": high, "dst": leaf, "interaction_type": "reply"})
    case2.append({"src": ids[19], "dst": low, "interaction_type": "share"})

    # A duplicated triangle makes every node tie, so the smallest ID must win.
    triangle = ids[29:32]
    case3 = []
    for a, b in ((triangle[0], triangle[1]),
                 (triangle[1], triangle[2]),
                 (triangle[2], triangle[0])):
        case3.extend([
            {"src": a, "dst": b, "interaction_type": "like"},
            {"src": b, "dst": a, "interaction_type": "reply"},
        ])

    for index, edges in enumerate((case1, case2, case3), start=1):
        with open(INPUT, "w") as f:
            json.dump(edges, f)
        expected = get_expected_result()
        actual = run_compiled_program()
        assert actual == expected, (
            f"The compiled program failed generated input {index}.\n"
            f"Expected: '{expected}'\nGot: '{actual}'"
        )
TEST_EOF

status=0
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
