#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import subprocess
import sys

import pytest

SCRIPT = "/home/user/generate_features.py"
DATA_DIR = "/home/user/data"
TOTAL_FILE = "/home/user/total_energy.txt"
FEATURES_FILE = "/home/user/features.csv"


def compute_expected_values():
    total_energy = 0.0
    csv_lines = ["graph_id,energy"]

    for i in range(100):
        filepath = f'/home/user/data/graph_{i}.txt'
        degrees = {}
        if os.path.exists(filepath):
            with open(filepath, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    u, v = map(int, line.split(','))
                    degrees[u] = degrees.get(u, 0) + 1
                    degrees[v] = degrees.get(v, 0) + 1

        energy = sum(deg * math.sin(v + 1.2345) for v, deg in degrees.items())
        csv_lines.append(f"{i},{energy:.8f}")
        total_energy += energy

    expected_total_energy_str = f"{total_energy:.8f}"
    return expected_total_energy_str, csv_lines


def run_submission():
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def verify_current_outputs():
    expected_total, expected_lines = compute_expected_values()

    assert os.path.exists(TOTAL_FILE), f"File {TOTAL_FILE} is missing."
    with open(TOTAL_FILE, 'r') as f:
        actual_total = f.read().strip()
    assert actual_total == expected_total, (
        f"Total energy in {TOTAL_FILE} is incorrect. "
        f"Expected '{expected_total}', got '{actual_total}'."
    )

    assert os.path.exists(FEATURES_FILE), f"File {FEATURES_FILE} is missing."
    with open(FEATURES_FILE, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert len(actual_lines) == len(expected_lines), (
        f"Incorrect number of lines in {FEATURES_FILE}. "
        f"Expected {len(expected_lines)}, got {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch in {FEATURES_FILE} at line {i + 1}. "
            f"Expected '{expected}', got '{actual}'."
        )


def test_00_script_exists_uses_parallelism_and_ordered_reduction():
    assert os.path.isfile(SCRIPT), f"Required Python script {SCRIPT} is missing."

    with open(SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT} is not valid Python: {exc}")

    module_aliases = set()
    imported_parallel_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "multiprocessing":
                    module_aliases.add(alias.asname or "multiprocessing")
        elif isinstance(node, ast.ImportFrom) and node.module == "multiprocessing":
            for alias in node.names:
                if alias.name in {"Pool", "Process"}:
                    imported_parallel_names.add(alias.asname or alias.name)

    assert module_aliases or imported_parallel_names, (
        "generate_features.py must import Python's multiprocessing module."
    )

    pool_constructed = False
    process_constructed = False
    pool_dispatch = False
    process_started = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name):
            if func.id in imported_parallel_names:
                if func.id.lower().endswith("process") or func.id == "Process":
                    process_constructed = True
                else:
                    pool_constructed = True
        elif isinstance(func, ast.Attribute):
            if isinstance(func.value, ast.Name) and func.value.id in module_aliases:
                if func.attr == "Pool":
                    pool_constructed = True
                elif func.attr == "Process":
                    process_constructed = True
            if func.attr in {"map", "starmap", "imap", "imap_unordered", "apply_async", "map_async", "starmap_async"}:
                pool_dispatch = True
            elif func.attr == "start":
                process_started = True

    assert (pool_constructed and pool_dispatch) or (process_constructed and process_started), (
        "The script must actually dispatch graph computations through multiprocessing Pool/Process workers."
    )

    ordered_reduction = False
    scopes = [tree] + [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
    for scope in scopes:
        sort_lines = []
        reduction_lines = []
        for node in ast.walk(scope):
            if node is not scope and isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
                continue
            if isinstance(node, ast.Call):
                if isinstance(node.func, ast.Name) and node.func.id == "sorted":
                    sort_lines.append(node.lineno)
                elif isinstance(node.func, ast.Attribute) and node.func.attr == "sort":
                    sort_lines.append(node.lineno)
                if isinstance(node.func, ast.Name) and node.func.id == "sum":
                    reduction_lines.append(node.lineno)
            elif isinstance(node, ast.AugAssign) and isinstance(node.op, ast.Add):
                reduction_lines.append(node.lineno)
        if any(sort_line < reduction_line for sort_line in sort_lines for reduction_line in reduction_lines):
            ordered_reduction = True
            break

    assert ordered_reduction, (
        "The script must sort collected graph results before performing the total-energy reduction."
    )

    for path in (TOTAL_FILE, FEATURES_FILE):
        if os.path.exists(path):
            os.remove(path)
    run_submission()


def test_total_energy_file():
    total_energy_file = "/home/user/total_energy.txt"
    assert os.path.exists(total_energy_file), f"File {total_energy_file} is missing."

    expected_total_energy_str, _ = compute_expected_values()

    with open(total_energy_file, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_total_energy_str, (
        f"Total energy in {total_energy_file} is incorrect. "
        f"Expected '{expected_total_energy_str}', got '{actual_content}'."
    )


def test_features_csv_file():
    features_csv_file = "/home/user/features.csv"
    assert os.path.exists(features_csv_file), f"File {features_csv_file} is missing."

    _, expected_csv_lines = compute_expected_values()

    with open(features_csv_file, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_csv_lines), (
        f"Incorrect number of lines in {features_csv_file}. "
        f"Expected {len(expected_csv_lines)}, got {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_csv_lines)):
        assert actual == expected, (
            f"Mismatch in {features_csv_file} at line {i + 1}. "
            f"Expected '{expected}', got '{actual}'."
        )


def test_zz_script_recomputes_for_changed_graphs():
    originals = {}
    for i in range(100):
        path = os.path.join(DATA_DIR, f"graph_{i}.txt")
        with open(path, "rb") as f:
            originals[path] = f.read()

    try:
        for i in range(100):
            path = os.path.join(DATA_DIR, f"graph_{i}.txt")
            edge_count = 2 + (i % 7)
            base = i * 3
            edges = []
            for j in range(edge_count):
                edges.append(f"{base},{base + j + 1}\n")
            if i % 4 == 0:
                edges.append(f"{base + 1},{base + edge_count + 2}\n")
            with open(path, "w", encoding="utf-8") as f:
                f.writelines(edges)

        for path in (TOTAL_FILE, FEATURES_FILE):
            if os.path.exists(path):
                os.remove(path)
        run_submission()
        verify_current_outputs()
    finally:
        for path, content in originals.items():
            with open(path, "wb") as f:
                f.write(content)
        subprocess.run(
            [sys.executable, SCRIPT],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=120,
            check=False,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
