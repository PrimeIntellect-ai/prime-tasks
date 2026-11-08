#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess

import pytest

OUTPUT_PATH = "/home/user/cycles_output.json"
LINEAGE_PATH = "/home/user/lineage.json"
SOURCE_PATH = "/home/user/find_cycles.cpp"
EXECUTABLE_PATH = "/home/user/find_cycles"
JSON_HEADER_PATH = "/home/user/json.hpp"


def test_cycles_output_exists_and_correct():
    assert os.path.exists(OUTPUT_PATH), f"File {OUTPUT_PATH} is missing. Did the C++ program run successfully?"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."

    with open(OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_PATH} does not contain valid JSON.")

    assert "cycles" in data, f"Key 'cycles' missing from {OUTPUT_PATH}."

    expected_cycles = [
        ["DS_A", "DS_B", "DS_C"],
        ["DS_E", "DS_F", "DS_G"],
    ]

    assert data["cycles"] == expected_cycles, (
        f"The cycles in {OUTPUT_PATH} do not match the expected output. "
        f"Expected {expected_cycles}, but got {data['cycles']}."
    )


def test_cpp_artifacts_exist():
    assert os.path.exists(SOURCE_PATH), f"C++ source file {SOURCE_PATH} is missing."
    assert os.path.exists(EXECUTABLE_PATH), f"Compiled executable {EXECUTABLE_PATH} is missing."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable."

    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a regular file."
    assert os.path.isfile(JSON_HEADER_PATH), f"JSON header {JSON_HEADER_PATH} is missing."
    assert os.path.getsize(JSON_HEADER_PATH) > 0, f"JSON header {JSON_HEADER_PATH} is empty."

    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r'^\s*#\s*include\s*[<\"][^>\"]*json\.hpp[>\"]', source, re.MULTILINE), (
        f"{SOURCE_PATH} does not include json.hpp."
    )


def expected_sccs(edges):
    graph = {}
    reverse = {}
    for edge in edges:
        source = edge["source"]
        target = edge["target"]
        graph.setdefault(source, []).append(target)
        graph.setdefault(target, [])
        reverse.setdefault(target, []).append(source)
        reverse.setdefault(source, [])

    visited = set()
    order = []

    def visit(node):
        if node in visited:
            return
        visited.add(node)
        for neighbor in graph[node]:
            visit(neighbor)
        order.append(node)

    for node in graph:
        visit(node)

    visited.clear()
    components = []

    def collect(node, component):
        if node in visited:
            return
        visited.add(node)
        component.append(node)
        for neighbor in reverse[node]:
            collect(neighbor, component)

    for node in reversed(order):
        if node not in visited:
            component = []
            collect(node, component)
            if len(component) >= 2:
                components.append(sorted(component))

    components.sort(key=lambda component: component[0])
    return components


def run_and_check(edges):
    with open(LINEAGE_PATH, "w", encoding="utf-8") as f:
        json.dump(edges, f)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    try:
        result = subprocess.run(
            [EXECUTABLE_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("find_cycles timed out on a changed lineage input.")

    assert result.returncode == 0, (
        f"find_cycles exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), "find_cycles did not create cycles_output.json."

    try:
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"find_cycles produced invalid JSON: {exc}")

    assert isinstance(data, dict), "Output must be a JSON object."
    assert set(data.keys()) == {"cycles"}, "Output must contain exactly the 'cycles' field."
    assert isinstance(data["cycles"], list), "The 'cycles' field must be an array."

    expected = expected_sccs(edges)
    assert data["cycles"] == expected, (
        f"Incorrect SCC result for changed input. Expected {expected}, got {data['cycles']}."
    )


def test_recompiled_program_on_changed_inputs():
    with open(LINEAGE_PATH, "rb") as f:
        original_lineage = f.read()

    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-o", EXECUTABLE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"find_cycles.cpp does not compile with the required command.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    assert os.access(EXECUTABLE_PATH, os.X_OK), "Recompiled find_cycles is not executable."

    prefix = "N_" + secrets.token_hex(6) + "_"
    names = [prefix + str(i).zfill(2) for i in range(12)]

    structured = [
        {"source": names[0], "target": names[1]},
        {"source": names[1], "target": names[2]},
        {"source": names[2], "target": names[0]},
        {"source": names[2], "target": names[3]},
        {"source": names[3], "target": names[4]},
        {"source": names[4], "target": names[3]},
        {"source": names[4], "target": names[5]},
        {"source": names[6], "target": names[7]},
        {"source": names[7], "target": names[8]},
        {"source": names[9], "target": names[10]},
        {"source": names[10], "target": names[9]},
        {"source": names[10], "target": names[11]},
    ]

    rng = random.SystemRandom()
    random_edges = []
    for i in range(len(names) - 1):
        random_edges.append({"source": names[i], "target": names[i + 1]})
    for _ in range(28):
        source, target = rng.sample(names, 2)
        random_edges.append({"source": source, "target": target})
    rng.shuffle(random_edges)

    fixtures = [
        [],
        [
            {"source": names[0], "target": names[1]},
            {"source": names[1], "target": names[2]},
            {"source": names[3], "target": names[4]},
        ],
        structured,
        random_edges,
    ]

    try:
        for edges in fixtures:
            run_and_check(edges)
    finally:
        with open(LINEAGE_PATH, "wb") as f:
            f.write(original_lineage)
        subprocess.run(
            [EXECUTABLE_PATH],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
            check=False,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
