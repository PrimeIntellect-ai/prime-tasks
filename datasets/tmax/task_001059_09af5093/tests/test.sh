#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import json
import os
import re
import secrets
import sqlite3
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest


def fetch_json(url):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200, f"Expected 200 OK, got {response.status}"
        return json.loads(response.read().decode("utf-8"))


def test_nginx_routing_health():
    """Test that Nginx routes /api/health to Flask correctly."""
    url = "http://127.0.0.1:8080/api/health"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected 200 OK, got {response.status}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx at {url}: {e}")


def test_nginx_has_api_prefix_proxy_and_routes_data():
    config_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(config_path)
    config = open(config_path, encoding="utf-8").read()
    uncommented = re.sub(r"#.*", "", config)
    match = re.search(r"location\s+(?:\^~\s+)?/api/\s*\{([^{}]*)\}", uncommented, re.S)
    assert match, "Nginx must define a prefix location for all /api/ requests"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:5000\s*;", match.group(1)), \
        "The /api/ location must proxy to 127.0.0.1:5000 without stripping /api/"
    checked = subprocess.run(
        ["nginx", "-t", "-c", config_path], capture_output=True, text=True
    )
    assert checked.returncode == 0, checked.stderr

    with sqlite3.connect("/home/user/data/backup.db") as conn:
        expected = [list(row) for row in conn.execute("SELECT * FROM dependencies").fetchall()]
    assert fetch_json("http://127.0.0.1:8080/api/data") == expected


def test_flask_uses_backup_db():
    """Test that Flask API uses the backup.db instead of prod.db."""
    app_py_path = "/home/user/api/app.py"
    assert os.path.isfile(app_py_path), f"Flask app file missing at {app_py_path}"
    with open(app_py_path, 'r') as f:
        content = f.read()

    assert "backup.db" in content, "The Flask app does not appear to be updated to use backup.db."
    assert "prod.db" not in content or content.index("backup.db") > -1, "The Flask app still uses prod.db."

    marker = "live_" + secrets.token_hex(8)
    with sqlite3.connect("/home/user/data/backup.db") as conn:
        conn.execute(
            "INSERT INTO dependencies(parent_name, child_name) VALUES (?, ?)",
            ("root_node", marker),
        )
        conn.commit()
    try:
        rows = fetch_json("http://127.0.0.1:8080/api/data")
        assert any(len(row) >= 3 and row[1] == "root_node" and row[2] == marker for row in rows), \
            "The live Flask service did not read newly inserted backup.db data"
    finally:
        with sqlite3.connect("/home/user/data/backup.db") as conn:
            conn.execute("DELETE FROM dependencies WHERE child_name = ?", (marker,))
            conn.commit()


def test_exported_graph():
    """Test that the exported graph JSON exists and has correct format."""
    export_path = "/home/user/exported_graph.json"
    assert os.path.isfile(export_path), f"Expected exported graph at {export_path} is missing."

    with open(export_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Exported graph is not a valid JSON file.")

    assert isinstance(data, list), "Exported graph JSON should be a list of dictionaries."
    if len(data) > 0:
        for item in data:
            assert isinstance(item, dict), "Items in exported graph list must be dictionaries."
            assert "parent" in item, "Missing 'parent' key in exported graph item."
            assert "child" in item, "Missing 'child' key in exported graph item."


def expected_reachable_edges():
    with sqlite3.connect("/home/user/data/backup.db") as conn:
        edges = [(p, c) for p, c in conn.execute(
            "SELECT parent_name, child_name FROM dependencies"
        ).fetchall()]
    reachable = {"root_node"}
    changed = True
    while changed:
        changed = False
        for parent, child in edges:
            if parent in reachable and child not in reachable:
                reachable.add(child)
                changed = True
    return collections.Counter((p, c) for p, c in edges if p in reachable)


def validate_export_file():
    with open("/home/user/exported_graph.json", encoding="utf-8") as f:
        data = json.load(f)
    assert isinstance(data, list) and data, "The reachable graph must not be empty"
    for item in data:
        assert isinstance(item, dict)
        assert set(item) == {"parent", "child"}
        assert isinstance(item["parent"], str) and isinstance(item["child"], str)
    actual = collections.Counter((x["parent"], x["child"]) for x in data)
    assert actual == expected_reachable_edges(), "Export does not contain exactly all reachable edges"


def run_export_direct():
    script = "/home/user/export_graph.py"
    assert os.path.isfile(script), f"Exporter missing at {script}"
    assert os.access(script, os.X_OK), "export_graph.py is not executable"
    if os.path.exists("/home/user/exported_graph.json"):
        os.unlink("/home/user/exported_graph.json")
    result = subprocess.run([script], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
    assert os.path.isfile("/home/user/exported_graph.json")
    validate_export_file()


def trace_export_sql():
    wrapper = r'''
import json, runpy, sqlite3, sys
records = []
real_connect = sqlite3.connect
missing = object()
class CursorProxy:
    def __init__(self, inner): self.inner = inner
    def execute(self, sql, params=missing):
        records.append([str(sql), params is not missing, repr(params)])
        if params is missing: return self.inner.execute(sql)
        return self.inner.execute(sql, params)
    def __iter__(self): return iter(self.inner)
    def __getattr__(self, name): return getattr(self.inner, name)
class ConnectionProxy:
    def __init__(self, inner): self.inner = inner
    def cursor(self, *a, **k): return CursorProxy(self.inner.cursor(*a, **k))
    def execute(self, sql, params=missing):
        records.append([str(sql), params is not missing, repr(params)])
        if params is missing: return self.inner.execute(sql)
        return self.inner.execute(sql, params)
    def __enter__(self):
        self.inner.__enter__()
        return self
    def __exit__(self, *a): return self.inner.__exit__(*a)
    def __getattr__(self, name): return getattr(self.inner, name)
def connect(*a, **k): return ConnectionProxy(real_connect(*a, **k))
sqlite3.connect = connect
try:
    sys.argv = [sys.argv[1]]
    runpy.run_path(sys.argv[0], run_name="__main__")
finally:
    with open(sys.argv[2] if len(sys.argv) > 2 else "/tmp/export_trace.json", "w") as f:
        json.dump(records, f)
'''
    # Keep the trace destination available after sys.argv is replaced.
    wrapper = wrapper.replace(
        'sys.argv = [sys.argv[1]]\n    runpy.run_path(sys.argv[0], run_name="__main__")',
        'target, trace_path = sys.argv[1], sys.argv[2]\n    sys.argv = [target]\n    runpy.run_path(target, run_name="__main__")'
    ).replace(
        'with open(sys.argv[2] if len(sys.argv) > 2 else "/tmp/export_trace.json", "w") as f:',
        'with open(trace_path, "w") as f:'
    )
    with tempfile.TemporaryDirectory() as td:
        wrapper_path = os.path.join(td, "trace.py")
        trace_path = os.path.join(td, "trace.json")
        with open(wrapper_path, "w", encoding="utf-8") as f:
            f.write(wrapper)
        result = subprocess.run(
            ["python3", wrapper_path, "/home/user/export_graph.py", trace_path],
            capture_output=True, text=True, timeout=15,
        )
        assert result.returncode == 0, result.stderr
        with open(trace_path, encoding="utf-8") as f:
            records = json.load(f)
    recursive = []
    for sql, supplied, params in records:
        if re.search(r"\bWITH\s+RECURSIVE\b", sql, re.I):
            recursive.append((sql, supplied, params))
    assert recursive, "The exporter did not execute a recursive CTE"
    assert any(
        supplied
        and re.search(r"(?:\?|[:@$][A-Za-z_]\w*)", sql)
        and "root_node" in params
        for sql, supplied, params in recursive
    ), "The executed recursive CTE must parameterize the root_node value"


def test_exporter_execution_cte_and_dynamic_contents():
    source = open("/home/user/export_graph.py", encoding="utf-8").read()
    ast.parse(source)
    assert "/home/user/data/backup.db" in source
    run_export_direct()
    trace_export_sql()

    suffix = secrets.token_hex(8)
    first = "reachable_" + suffix
    second = "descendant_" + suffix
    isolated = "isolated_" + suffix
    with sqlite3.connect("/home/user/data/backup.db") as conn:
        conn.executemany(
            "INSERT INTO dependencies(parent_name, child_name) VALUES (?, ?)",
            [("root_node", first), (first, second), (isolated, isolated + "_child")],
        )
        conn.commit()
    try:
        run_export_direct()
    finally:
        with sqlite3.connect("/home/user/data/backup.db") as conn:
            conn.execute(
                "DELETE FROM dependencies WHERE parent_name IN (?, ?) OR child_name IN (?, ?)",
                (first, isolated, first, second),
            )
            conn.commit()
        restore = subprocess.run(
            ["/home/user/export_graph.py"], capture_output=True, text=True, timeout=15
        )
        assert restore.returncode == 0, restore.stderr


def test_detect_corruption_evil_corpus():
    """Test that the detect_corruption script correctly identifies evil (cyclic) graphs."""
    script_path = "/home/user/detect_corruption.py"
    evil_dir = "/app/corpora/evil/"

    assert os.path.isfile(script_path), f"Script missing at {script_path}"

    result = subprocess.run(["python3", script_path, evil_dir], capture_output=True, text=True)
    output = result.stdout.strip()

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.json')]
    bypassed = []

    for f in evil_files:
        expected_str = f"{f}: EVIL"
        if expected_str not in output:
            bypassed.append(f)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed)}")


def test_detect_corruption_clean_corpus():
    """Test that the detect_corruption script correctly identifies clean (DAG) graphs."""
    script_path = "/home/user/detect_corruption.py"
    clean_dir = "/app/corpora/clean/"

    assert os.path.isfile(script_path), f"Script missing at {script_path}"

    result = subprocess.run(["python3", script_path, clean_dir], capture_output=True, text=True)
    output = result.stdout.strip()

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.json')]
    modified = []

    for f in clean_files:
        expected_str = f"{f}: CLEAN"
        if expected_str not in output:
            modified.append(f)

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(modified)}")


def test_detector_on_unpredictable_mixed_graphs_with_exact_output():
    script = "/home/user/detect_corruption.py"
    assert os.path.isfile(script)
    assert os.access(script, os.X_OK), "detect_corruption.py is not executable"
    token = secrets.token_hex(10)
    a, b, c, d, e = [f"{token}_{x}" for x in "abcde"]
    cases = [
        ("CLEAN", []),
        ("CLEAN", [
            {"parent": a, "child": b}, {"parent": a, "child": c},
            {"parent": b, "child": d}, {"parent": c, "child": e},
        ]),
        ("EVIL", [{"parent": a, "child": a}]),
        ("EVIL", [
            {"parent": a, "child": b}, {"parent": b, "child": c},
            {"parent": c, "child": d}, {"parent": d, "child": a},
        ]),
        ("EVIL", [
            {"parent": a, "child": b}, {"parent": c, "child": d},
            {"parent": d, "child": e}, {"parent": e, "child": c},
        ]),
    ]
    # Random names and assignment prevent filename/status lookup solutions.
    import random
    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory() as corpus:
        expected = []
        for status, graph in cases:
            filename = secrets.token_hex(12) + ".json"
            with open(os.path.join(corpus, filename), "w", encoding="utf-8") as f:
                json.dump(graph, f)
            expected.append(f"{filename}: {status}")
        result = subprocess.run([script, corpus], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, result.stderr
        assert result.stderr == "", "Detector must not emit diagnostics for valid inputs"
        actual = result.stdout.splitlines()
        assert collections.Counter(actual) == collections.Counter(expected), \
            "Detector must print exactly one correct line for every JSON graph"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
