#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import itertools
import random
import shutil
import subprocess
import tempfile
import pytest


def test_active_edges_csv():
    csv_path = "/home/user/active_edges.csv"
    assert os.path.isfile(csv_path), f"CSV file {csv_path} is missing."

    expected_edges = {
        ("1", "2"), ("2", "3"), ("3", "1"),
        ("2", "4"), ("4", "6"), ("6", "2"),
        ("4", "7"), ("7", "1"), ("1", "6"),
        ("7", "2")
    }

    actual_edges = set()
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                assert len(row) == 2, f"Invalid row format in CSV: {row}"
                actual_edges.add((row[0].strip(), row[1].strip()))

    assert actual_edges == expected_edges, f"CSV edges do not match expected. Missing: {expected_edges - actual_edges}, Unexpected: {actual_edges - expected_edges}"


def test_c_program_exists():
    c_path = "/home/user/find_triangles.c"
    exe_path = "/home/user/find_triangles"

    assert os.path.isfile(c_path), f"C source file {c_path} is missing."
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} is missing."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {exe_path} is not a compiled executable."


def test_triangles_jsonl():
    jsonl_path = "/home/user/triangles.jsonl"
    assert os.path.isfile(jsonl_path), f"JSONL file {jsonl_path} is missing."

    expected_triangles = {
        tuple([1, 2, 3]),
        tuple([2, 4, 6])
    }

    actual_triangles = set()
    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON line in {jsonl_path}: {line}")

            assert "triangle" in data, f"Missing 'triangle' key in JSON line: {line}"
            actual_triangles.add(tuple(data["triangle"]))

    assert actual_triangles == expected_triangles, f"Triangles in JSONL do not match expected. Found: {actual_triangles}"


def test_final_report_json():
    report_path = "/home/user/final_report.json"
    assert os.path.isfile(report_path), f"Final report JSON {report_path} is missing."

    with open(report_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {report_path}")

    assert "metadata" in data, "Missing 'metadata' key in final report."
    assert "total_triangles" in data["metadata"], "Missing 'total_triangles' in metadata."
    assert data["metadata"]["total_triangles"] == 2, f"Expected 2 total triangles, got {data['metadata']['total_triangles']}"

    assert "data" in data, "Missing 'data' key in final report."

    expected_data = [
        [1, 2, 3],
        [2, 4, 6]
    ]

    assert data["data"] == expected_data, f"Data array does not match expected. Got: {data['data']}"


def expected_triangles(edges):
    nodes = sorted({n for edge in edges for n in edge})
    edge_set = set(edges)
    result = set()
    for triple in itertools.combinations(nodes, 3):
        if any(
            (p[0], p[1]) in edge_set
            and (p[1], p[2]) in edge_set
            and (p[2], p[0]) in edge_set
            for p in itertools.permutations(triple)
        ):
            result.add(triple)
    return result


def parse_program_output(output, executable):
    triangles = []
    for line in output.splitlines():
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            pytest.fail(f"{executable} emitted invalid JSONL: {line!r}: {exc}")
        assert isinstance(item, dict) and "triangle" in item, \
            f"{executable} emitted a line without a triangle: {item!r}"
        triangle = item["triangle"]
        assert isinstance(triangle, list) and len(triangle) == 3, \
            f"{executable} emitted an invalid triangle: {triangle!r}"
        assert all(type(value) is int for value in triangle), \
            f"{executable} emitted non-integer node IDs: {triangle!r}"
        assert triangle == sorted(triangle) and len(set(triangle)) == 3, \
            f"{executable} did not normalize its triangle: {triangle!r}"
        triangles.append(tuple(triangle))
    assert len(triangles) == len(set(triangles)), \
        f"{executable} emitted duplicate normalized triangles: {triangles!r}"
    return set(triangles)


def test_submitted_c_program_on_runtime_graphs():
    source = "/home/user/find_triangles.c"
    submitted_exe = "/home/user/find_triangles"
    csv_path = "/home/user/active_edges.csv"

    build_dir = tempfile.mkdtemp(prefix="triangle-verifier-")
    rebuilt_exe = os.path.join(build_dir, "find_triangles")
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", source, "-o", rebuilt_exe],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, \
        f"Failed to compile {source}:\n{compile_result.stderr}"

    rng = random.SystemRandom()
    labels = list(range(1, 10))
    rng.shuffle(labels)

    constructed = {
        (labels[0], labels[1]), (labels[1], labels[2]), (labels[2], labels[0]),
        (labels[3], labels[5]), (labels[5], labels[4]), (labels[4], labels[3]),
        (labels[0], labels[6]), (labels[7], labels[1])
    }
    dag_order = labels[:]
    rng.shuffle(dag_order)
    dag = {
        (dag_order[i], dag_order[j])
        for i in range(len(dag_order))
        for j in range(i + 1, len(dag_order))
        if rng.random() < 0.35
    }
    random_graph_1 = {
        (a, b) for a in labels for b in labels
        if a != b and rng.random() < 0.24
    }
    random_graph_2 = {
        (a, b) for a in labels for b in labels
        if a != b and rng.random() < 0.39
    }
    cases = [constructed, dag, random_graph_1, random_graph_2]

    with open(csv_path, "rb") as f:
        original_csv = f.read()

    try:
        for case_number, edges in enumerate(cases, 1):
            rows = list(edges)
            rng.shuffle(rows)
            with open(csv_path, "w", encoding="utf-8", newline="") as f:
                for source_id, target_id in rows:
                    f.write(f"{source_id},{target_id}\n")

            expected = expected_triangles(edges)
            for executable in (submitted_exe, rebuilt_exe):
                result = subprocess.run(
                    [executable],
                    cwd="/home/user",
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=5,
                )
                assert result.returncode == 0, \
                    f"{executable} failed on runtime graph {case_number}: {result.stderr}"
                actual = parse_program_output(result.stdout, executable)
                assert actual == expected, \
                    f"{executable} produced wrong triangles on runtime graph {case_number}. Expected {expected}, got {actual}"
    finally:
        with open(csv_path, "wb") as f:
            f.write(original_csv)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
