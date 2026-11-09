#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

import networkx as nx

DB_PATH = "/home/user/knowledge_graph.db"
JSON_PATH = "/home/user/top_triplets.json"
HOME = Path("/home/user")


def expected_results():
    conn = sqlite3.connect(DB_PATH)
    try:
        papers = conn.execute("SELECT id, year FROM papers").fetchall()
        citations = conn.execute("SELECT source, target FROM citations").fetchall()
    finally:
        conn.close()

    graph = nx.DiGraph()
    graph.add_nodes_from(paper_id for paper_id, _ in papers)
    graph.add_edges_from(citations)
    ranks = nx.pagerank(graph)

    years = dict(papers)
    edges = set(citations)
    triangles = []
    for a, b in edges:
        for b2, c in edges:
            if b2 != b or (a, c) not in edges:
                continue
            if all(years.get(node, -1) >= 2010 for node in (a, b, c)):
                triangles.append({
                    "A": a,
                    "B": b,
                    "C": c,
                    "score": ranks[a] + ranks[b] + ranks[c],
                })

    triangles.sort(key=lambda item: (-item["score"], item["A"], item["B"], item["C"]))
    return triangles[:3]


def load_and_check(expected):
    assert os.path.exists(JSON_PATH), f"Output file missing at {JSON_PATH}"
    with open(JSON_PATH, "r") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {JSON_PATH} is not valid JSON") from exc

    assert isinstance(data, list), "JSON root must be a list"
    assert len(data) == len(expected), f"Expected exactly {len(expected)} triplets, but found {len(data)}"

    for i, wanted in enumerate(expected):
        item = data[i]
        assert isinstance(item, dict), f"Item at index {i} is not a dictionary"
        for key in ["A", "B", "C", "score"]:
            assert key in item, f"Item at index {i} is missing key '{key}'"
        assert item["A"] == wanted["A"], f"Expected A={wanted['A']} at rank {i+1}, got {item['A']}"
        assert item["B"] == wanted["B"], f"Expected B={wanted['B']} at rank {i+1}, got {item['B']}"
        assert item["C"] == wanted["C"], f"Expected C={wanted['C']} at rank {i+1}, got {item['C']}"
        assert isinstance(item["score"], (int, float)) and not isinstance(item["score"], bool), \
            f"Score at rank {i+1} must be a number"
        assert math.isfinite(item["score"]), f"Score at rank {i+1} must be finite"
        assert math.isclose(item["score"], wanted["score"], rel_tol=1e-8, abs_tol=1e-10), \
            f"Incorrect PageRank score at rank {i+1}: expected {wanted['score']}, got {item['score']}"

    scores = [item["score"] for item in data]
    assert scores == sorted(scores, reverse=True), "Scores are not sorted in descending order"
    return data


def has_parameterized_pattern_query(path):
    try:
        source = path.read_text(errors="ignore")
        tree = ast.parse(source)
    except (OSError, SyntaxError):
        return False

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = value

    def resolve_text(node, seen=None):
        seen = set() if seen is None else seen
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name) and node.id not in seen and node.id in assignments:
            return resolve_text(assignments[node.id], seen | {node.id})
        if isinstance(node, ast.JoinedStr):
            return "".join(
                value.value for value in node.values
                if isinstance(value, ast.Constant) and isinstance(value.value, str)
            )
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left = resolve_text(node.left, seen)
            right = resolve_text(node.right, seen)
            if left is not None and right is not None:
                return left + right
        return None

    def contains_2010(node, seen=None):
        seen = set() if seen is None else seen
        if isinstance(node, ast.Constant) and node.value == 2010:
            return True
        if isinstance(node, ast.Name) and node.id not in seen and node.id in assignments:
            return contains_2010(assignments[node.id], seen | {node.id})
        return any(contains_2010(child, seen) for child in ast.iter_child_nodes(node))

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr != "execute" or len(node.args) < 2:
            continue
        query = resolve_text(node.args[0])
        if not query:
            continue
        lowered = query.lower()
        has_placeholder = "?" in query or any(token in query for token in (":year", ":threshold", "$year", "$threshold"))
        if ("citations" in lowered and "papers" in lowered and "year" in lowered
                and has_placeholder and contains_2010(node.args[1])):
            return True
    return False


def restore_database(backup):
    for suffix in ("-wal", "-shm"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    shutil.copy2(backup, DB_PATH)


def run_script(path):
    try:
        os.remove(JSON_PATH)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        [sys.executable, str(path)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert result.returncode == 0, f"Script {path} failed: {result.stderr[-1000:]}"


def test_top_triplets_json():
    scripts = sorted(p for p in HOME.rglob("*.py") if p.is_file() and not any(part.startswith(".") for part in p.relative_to(HOME).parts))
    assert scripts, "No Python script was written under /home/user"
    assert any(has_parameterized_pattern_query(path) for path in scripts), \
        "No parameterized SQLite query using the 2010 threshold was found for the triangle/year pattern"

    fd, backup = tempfile.mkstemp(prefix="knowledge_graph_", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup)
    successful_script = None
    errors = []

    try:
        for script in scripts:
            try:
                restore_database(backup)
                original_expected = expected_results()
                run_script(script)
                load_and_check(original_expected)

                conn = sqlite3.connect(DB_PATH)
                try:
                    conn.execute("UPDATE papers SET year = 2009 WHERE id = 10")
                    conn.commit()
                finally:
                    conn.close()
                changed_expected = expected_results()
                run_script(script)
                load_and_check(changed_expected)

                restore_database(backup)
                original_expected = expected_results()
                run_script(script)
                data = load_and_check(original_expected)
                successful_script = script
                break
            except Exception as exc:
                errors.append(f"{script}: {exc}")

        assert successful_script is not None, "No submitted Python script generated correct results when executed. " + " | ".join(errors[-3:])

        expected_triplets = [
            {"A": 10, "B": 11, "C": 12},
            {"A": 30, "B": 31, "C": 32},
            {"A": 20, "B": 21, "C": 22},
        ]
        assert len(data) == 3, f"Expected exactly 3 triplets, but found {len(data)}"
        for i, expected in enumerate(expected_triplets):
            assert data[i]["A"] == expected["A"], f"Expected A={expected['A']} at rank {i+1}, got {data[i]['A']}"
            assert data[i]["B"] == expected["B"], f"Expected B={expected['B']} at rank {i+1}, got {data[i]['B']}"
            assert data[i]["C"] == expected["C"], f"Expected C={expected['C']} at rank {i+1}, got {data[i]['C']}"
    finally:
        restore_database(backup)
        os.remove(backup)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
