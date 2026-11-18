#!/bin/bash
mkdir -p /logs/verifier
BASE_DIR=/app/vendored/py-sync-server-1.0.0

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import concurrent.futures
import importlib.util
import json
import os
import random
import re
import socket
import subprocess

import pytest
import requests

BASE_DIR = "/app/vendored/py-sync-server-1.0.0"


def expected_convergence(data, threshold):
    val = float(sum(data))
    while val >= threshold:
        delta = val * 0.1
        val -= delta
    return val


def assert_close(actual, expected):
    actual = float(actual)
    tolerance = max(1e-10, abs(expected) * 1e-10)
    assert abs(actual - expected) <= tolerance, f"Expected {expected}, got {actual}"


def load_recovered_module():
    path = os.path.join(BASE_DIR, "compute_utils.py")
    spec = importlib.util.spec_from_file_location("recovered_compute_utils", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_compute_utils_py_exists():
    """Check that compute_utils.py has been recovered."""
    py_path = os.path.join(BASE_DIR, "compute_utils.py")
    assert os.path.isfile(py_path), f"File {py_path} was not recovered."
    assert os.path.getsize(py_path) > 0, "Recovered compute_utils.py is empty."


def test_recovered_algorithm_and_required_assertion():
    path = os.path.join(BASE_DIR, "compute_utils.py")
    with open(path, "r", encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source, filename=path)
    functions = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "calculate_convergence"]
    assert functions, "calculate_convergence is missing from compute_utils.py"

    strict_delta_assert = False
    for node in ast.walk(functions[0]):
        if not isinstance(node, ast.Assert):
            continue
        names = {n.id.lower() for n in ast.walk(node.test) if isinstance(n, ast.Name)}
        strict_comparison = any(
            isinstance(op, (ast.Lt, ast.Gt))
            for comparison in ast.walk(node.test)
            if isinstance(comparison, ast.Compare)
            for op in comparison.ops
        )
        if strict_comparison and any("delta" in name for name in names):
            strict_delta_assert = True
    assert strict_delta_assert, "calculate_convergence must assert that the intermediate delta is strictly decreasing"

    module = load_recovered_module()
    cases = [
        ([5, 5], 10),       # exercises the corrected >= boundary
        ([1, 2, 3], 100),   # no iterations
        ([40, 2, 9], 7),
        ([250, 125, 25], 3),
        ([7, 11, 13, 17], 19),
    ]
    rng = random.SystemRandom()
    for _ in range(12):
        values = [rng.randint(1, 200) for _ in range(rng.randint(1, 8))]
        threshold = rng.randint(1, sum(values) + 30)
        cases.append((values, threshold))

    observed = []
    for values, threshold in cases:
        result = module.calculate_convergence(values, threshold)
        expected = expected_convergence(values, threshold)
        assert_close(result, expected)
        observed.append(float(result))
    assert len({round(value, 10) for value in observed}) > 3, "Algorithm appears to return a constant result"


def _lock_orders(function_node):
    orders = set()
    for outer in ast.walk(function_node):
        if not isinstance(outer, ast.With):
            continue
        outer_names = [
            item.context_expr.id
            for item in outer.items
            if isinstance(item.context_expr, ast.Name) and item.context_expr.id in {"lock_A", "lock_B"}
        ]
        if len(outer_names) >= 2:
            orders.add(tuple(outer_names[:2]))
        if len(outer_names) != 1:
            continue
        for statement in outer.body:
            for inner in ast.walk(statement):
                if not isinstance(inner, ast.With):
                    continue
                inner_names = [
                    item.context_expr.id
                    for item in inner.items
                    if isinstance(item.context_expr, ast.Name) and item.context_expr.id in {"lock_A", "lock_B"}
                ]
                for name in inner_names:
                    if name != outer_names[0]:
                        orders.add((outer_names[0], name))
    return orders


def test_lock_acquisition_order_is_consistent():
    path = os.path.join(BASE_DIR, "server.py")
    with open(path, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=path)
    functions = {n.name: n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    assert "do_POST" in functions and "handle_tcp" in functions
    http_orders = _lock_orders(functions["do_POST"])
    tcp_orders = _lock_orders(functions["handle_tcp"])
    assert len(http_orders) == 1, f"HTTP handler does not have one consistent lock order: {http_orders}"
    assert len(tcp_orders) == 1, f"TCP handler does not have one consistent lock order: {tcp_orders}"
    assert http_orders == tcp_orders, f"Handlers acquire locks in different orders: HTTP={http_orders}, TCP={tcp_orders}"


def test_makefile_uses_python3_and_run_target():
    result = subprocess.run(["make", "-n", "run"], cwd=BASE_DIR, text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, f"make run is broken: {result.stdout}{result.stderr}"
    command = result.stdout + result.stderr
    assert re.search(r"(?:^|[\s/])python3(?:\.[0-9]+)?(?:\s|$)", command), f"make run does not use Python 3: {command}"


def test_http_endpoint():
    """Test the HTTP endpoint for correct response and auth."""
    url = "http://127.0.0.1:8080/sync"
    headers = {"Authorization": "Bearer secret-token-123"}
    payload = {"data": [10, 20, 30], "threshold": 5}

    resp_no_auth = requests.post(url, json=payload, timeout=5)
    assert resp_no_auth.status_code in (401, 403), "HTTP endpoint should reject requests without valid auth."

    resp = requests.post(url, headers=headers, json=payload, timeout=5)
    assert resp.status_code == 200, f"HTTP endpoint failed with status {resp.status_code}: {resp.text}"
    data = resp.json()
    assert "result" in data, "Response JSON missing 'result' key."
    expected = expected_convergence([10, 20, 30], 5)
    result = float(data["result"])
    assert abs(result - expected) < 1.0, f"Expected converged value around {expected}, got {result}"


def tcp_request(values, threshold, timeout=5.0):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(("127.0.0.1", 8081))
        message = f"{','.join(str(x) for x in values)}|{threshold}\n"
        s.sendall(message.encode())
        return s.recv(1024).decode("utf-8").strip()
    finally:
        s.close()


def test_tcp_endpoint():
    """Test the TCP endpoint for correct response."""
    response = tcp_request([10, 20, 30], 5)
    assert response, "No response received from TCP endpoint."
    expected = expected_convergence([10, 20, 30], 5)
    result = float(response)
    assert abs(result - expected) < 1.0, f"Expected converged value around {expected}, got {result}"


def test_endpoints_on_varied_runtime_inputs():
    rng = random.SystemRandom()
    cases = [([8, 12], 20), ([3, 4], 50), ([100, 30, 7], 9)]
    for _ in range(9):
        values = [rng.randint(1, 150) for _ in range(rng.randint(1, 7))]
        threshold = rng.randint(1, sum(values) + 20)
        cases.append((values, threshold))

    url = "http://127.0.0.1:8080/sync"
    headers = {"Authorization": "Bearer secret-token-123"}
    for values, threshold in cases:
        expected = expected_convergence(values, threshold)
        response = requests.post(url, headers=headers, json={"data": values, "threshold": threshold}, timeout=5)
        assert response.status_code == 200, response.text
        body = response.json()
        assert "result" in body
        assert_close(body["result"], expected)

        tcp_result = tcp_request(values, threshold)
        assert tcp_result, "No response received from TCP endpoint"
        assert_close(tcp_result, expected)


def make_http_request(case=None):
    values, threshold = case or ([10, 20, 30], 5)
    url = "http://127.0.0.1:8080/sync"
    headers = {"Authorization": "Bearer secret-token-123"}
    payload = {"data": values, "threshold": threshold}
    resp = requests.post(url, headers=headers, json=payload, timeout=5)
    if resp.status_code != 200:
        return False
    try:
        assert_close(resp.json()["result"], expected_convergence(values, threshold))
        return True
    except Exception:
        return False


def make_tcp_request(case=None):
    values, threshold = case or ([10, 20, 30], 5)
    try:
        response = tcp_request(values, threshold)
        if not response:
            return False
        assert_close(response, expected_convergence(values, threshold))
        return True
    except Exception:
        return False


def test_concurrency_no_deadlock():
    """Test both endpoints concurrently to ensure deadlocks are fixed."""
    num_requests = 50
    rng = random.SystemRandom()
    cases = []
    for _ in range(num_requests // 2):
        values = [rng.randint(1, 100) for _ in range(rng.randint(2, 6))]
        cases.append((values, rng.randint(1, sum(values))))

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        futures = []
        for case in cases:
            futures.append(executor.submit(make_http_request, case))
            futures.append(executor.submit(make_tcp_request, case))
        for future in concurrent.futures.as_completed(futures):
            try:
                results.append(future.result())
            except Exception as exc:
                pytest.fail(f"Concurrent request failed with exception: {exc}")

    assert len(results) == num_requests
    assert all(results), "Some concurrent requests failed, indicating a potential deadlock, wrong result, or server crash."
TEST_EOF

# Stop the agent-started instance so verification necessarily exercises the repaired
# Makefile rather than accepting an unrelated process already bound to the ports.
pkill -TERM -f '[s]erver\.py' 2>/dev/null || true
sleep 1

cd "$BASE_DIR" || { echo "0" > /logs/verifier/reward.txt; exit 0; }
make run >/tmp/verifier-server.log 2>&1 &

ready=0
for _ in $(seq 1 50); do
    if python3 - <<'PY'
import socket
for port in (8080, 8081):
    s = socket.socket()
    s.settimeout(0.2)
    try:
        s.connect(("127.0.0.1", port))
    except OSError:
        raise SystemExit(1)
    finally:
        s.close()
PY
    then
        ready=1
        break
    fi
    sleep 0.1
done

if [ "$ready" -ne 1 ]; then
    cat /tmp/verifier-server.log >&2 || true
    echo "0" > /logs/verifier/reward.txt
elif timeout 90s python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
