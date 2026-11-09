#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import math
import os
import sqlite3
import subprocess
import sys
import tempfile
import time

import pytest
import requests

DB_PATH = "/app/logs.db"
ANALYZER_PATH = "/app/analyzer.py"
TEST_PATH = "/app/test_analyzer.py"
URL = "http://127.0.0.1:8000/anomalies"
TOKEN_HEADERS = {"Authorization": "Bearer SCARLET-MACAW-77"}


def expected_anomalies(rows):
    if not rows:
        return []
    counts = [count for _, count in rows]
    if len(counts) < 2:
        return []
    mean = sum(counts) / len(counts)
    variance = sum((count - mean) ** 2 for count in counts) / (len(counts) - 1)
    threshold = mean + 3 * math.sqrt(variance)
    return sorted(ip for ip, count in rows if count > threshold)


def load_analyzer():
    assert os.path.isfile(ANALYZER_PATH), "Missing /app/analyzer.py"
    spec = importlib.util.spec_from_file_location("submitted_analyzer", ANALYZER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "get_anomalies", None)), "analyzer.py must define get_anomalies"
    return module


def make_database(rows):
    handle = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    handle.close()
    conn = sqlite3.connect(handle.name)
    try:
        conn.execute("CREATE TABLE access_logs (ip_address TEXT, request_count INTEGER)")
        conn.executemany("INSERT INTO access_logs VALUES (?, ?)", rows)
        conn.commit()
    finally:
        conn.close()
    return handle.name


def test_recovered_database_is_queryable():
    assert os.path.isfile(DB_PATH), "Recovered database /app/logs.db is missing"
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT ip_address, request_count FROM access_logs ORDER BY ip_address"
        ).fetchall()
    finally:
        conn.close()
    expected = sorted([
        ("192.168.1.1", 20),
        ("192.168.1.2", 35),
        ("192.168.1.3", 15),
        ("192.168.1.4", 40),
        ("192.168.1.5", 25),
        ("10.0.0.99", 4500),
        ("192.168.1.105", 5000),
    ])
    assert rows == expected


def test_analyzer_uses_sample_stddev_and_strict_comparison():
    analyzer = load_analyzer()
    cases = [
        [(f"198.51.100.{i}", 0) for i in range(10)] + [("198.51.100.250", 100)],
        [(f"203.0.113.{i}", 0) for i in range(9)]
        + [("203.0.113.9", 10), ("203.0.113.10", 100)],
        [
            ("192.168.1.1", 20),
            ("192.168.1.2", 35),
            ("192.168.1.3", 15),
            ("192.168.1.4", 40),
            ("192.168.1.5", 25),
            ("10.0.0.99", 4500),
            ("192.168.1.105", 5000),
        ],
    ]
    for rows in cases:
        path = make_database(rows)
        try:
            assert analyzer.get_anomalies(path) == expected_anomalies(rows)
        finally:
            os.unlink(path)


def test_test_analyzer_exists_and_is_real_regression_test():
    assert os.path.isfile(TEST_PATH), "Regression test /app/test_analyzer.py was not created."
    source = open(TEST_PATH, encoding="utf-8").read()
    tree = ast.parse(source, filename=TEST_PATH)

    imported_names = set()
    imports_analyzer = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "analyzer":
                    imports_analyzer = True
                    imported_names.add(alias.asname or "analyzer")
        elif isinstance(node, ast.ImportFrom) and node.module == "analyzer":
            imports_analyzer = True
            imported_names.update(alias.asname or alias.name for alias in node.names)

    mock_names = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if isinstance(value, (ast.List, ast.Tuple)) and value.elts and all(
                isinstance(item, ast.Tuple) and len(item.elts) == 2 for item in value.elts
            ):
                mock_names.update(target.id for target in targets if isinstance(target, ast.Name))

    def is_mock_argument(node):
        return (
            isinstance(node, ast.Name) and node.id in mock_names
        ) or (
            isinstance(node, (ast.List, ast.Tuple))
            and node.elts
            and all(isinstance(item, ast.Tuple) and len(item.elts) == 2 for item in node.elts)
        )

    calls_analyzer_with_mock = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not node.args or not is_mock_argument(node.args[0]):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in imported_names:
            calls_analyzer_with_mock = True
        elif isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
            if node.func.value.id in imported_names:
                calls_analyzer_with_mock = True

    assert imports_analyzer, "Regression test must import the analyzer"
    assert any(isinstance(node, ast.Assert) for node in ast.walk(tree)), "Regression test must contain an assertion"
    assert calls_analyzer_with_mock, "Regression test must call an imported analyzer function with mock (ip, count) tuples"

    result = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", TEST_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
    )
    assert result.returncode == 0, f"Regression test failed:\n{result.stdout}"


def test_http_server_unauthorized():
    try:
        response = requests.get(URL, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP server at {URL}: {exc}")
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing token, got {response.status_code}"

    response = requests.get(URL, headers={"Authorization": "Bearer WRONG-TOKEN"}, timeout=2)
    assert response.status_code == 401, f"Expected 401 Unauthorized for wrong token, got {response.status_code}"


def test_http_server_authorized():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("SELECT ip_address, request_count FROM access_logs").fetchall()
    finally:
        conn.close()

    try:
        response = requests.get(URL, headers=TOKEN_HEADERS, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP server at {URL}: {exc}")

    assert response.status_code == 200, f"Expected 200 OK for correct token, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "anomalous_ips" in data, "JSON response missing 'anomalous_ips' key."
    expected_ips = expected_anomalies(rows)
    assert sorted(data["anomalous_ips"]) == expected_ips, f"Expected anomalous IPs {expected_ips}, got {data['anomalous_ips']}"


def test_http_server_queries_the_recovered_database():
    conn = sqlite3.connect(DB_PATH)
    original = conn.execute("SELECT ip_address, request_count FROM access_logs").fetchall()
    changed = [(f"203.0.113.{i}", 0) for i in range(10)] + [("203.0.113.250", 100)]
    try:
        conn.execute("DELETE FROM access_logs")
        conn.executemany("INSERT INTO access_logs VALUES (?, ?)", changed)
        conn.commit()

        expected = expected_anomalies(changed)
        response = None
        for _ in range(5):
            response = requests.get(URL, headers=TOKEN_HEADERS, timeout=2)
            if response.status_code == 200 and response.json().get("anomalous_ips") == expected:
                break
            time.sleep(0.2)
        assert response.status_code == 200
        assert response.json().get("anomalous_ips") == expected, "Server did not reflect committed access_logs data"
    finally:
        conn.execute("DELETE FROM access_logs")
        conn.executemany("INSERT INTO access_logs VALUES (?, ?)", original)
        conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
