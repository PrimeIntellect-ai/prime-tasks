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
import json
import os
import secrets
import signal
import subprocess
import sys
import time

import pytest
import requests

URL = "http://127.0.0.1:8000/api/merged"
SERVER = "/home/user/server.py"
ENGINE = "/app/pylitecsv-1.0.0/pylitecsv/engine.py"


def get_json(params):
    try:
        response = requests.get(URL, params=params, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert isinstance(data, list), "Expected response to be a JSON list of dictionaries."
    assert all(isinstance(item, dict) for item in data), "Every merged row must be a dictionary."
    return data


def test_ready_file_exists():
    assert os.path.isfile("/home/user/ready.txt"), "The /home/user/ready.txt file was not created. Did the server start successfully?"
    with open("/home/user/ready.txt", encoding="utf-8") as f:
        assert f.read().strip() == "READY", "/home/user/ready.txt must contain READY"


def test_server_artifact_uses_builtin_http_server():
    assert os.path.isfile(SERVER), f"Missing file: {SERVER}"
    with open(SERVER, encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SERVER)
    uses_http_server = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import) and any(a.name == "http.server" for a in node.names):
            uses_http_server = True
        if isinstance(node, ast.ImportFrom) and (
            node.module == "http.server" or
            (node.module == "http" and any(a.name == "server" for a in node.names))
        ):
            uses_http_server = True
    assert uses_http_server, "server.py must use Python's built-in http.server"


def test_api_merged_endpoint_electronics():
    params = {
        "category": "Electronics",
        "sort": "sale_id",
        "order": "asc",
        "limit": 1,
        "offset": 1,
    }
    data = get_json(params)
    assert len(data) == 1, f"Expected exactly 1 item in the response, got {len(data)}. Data: {data}"
    item = data[0]
    assert str(item.get("sale_id")) == "2", f"Expected sale_id '2', got {item.get('sale_id')}"
    assert str(item.get("product_id")) == "102", f"Expected product_id '102', got {item.get('product_id')}"
    assert str(item.get("category")) == "Electronics", f"Expected category 'Electronics', got {item.get('category')}"
    assert str(item.get("name")) == "Headphones", f"Expected name 'Headphones', got {item.get('name')}"


def test_api_merged_endpoint_kitchen_desc():
    params = {
        "sort": "sale_id",
        "order": "desc",
        "limit": 2,
        "offset": 0,
    }
    data = get_json(params)
    assert len(data) == 2, f"Expected exactly 2 items in the response, got {len(data)}. Data: {data}"
    assert str(data[0].get("sale_id")) == "4", f"Expected first item sale_id '4', got {data[0].get('sale_id')}"
    assert str(data[1].get("sale_id")) == "3", f"Expected second item sale_id '3', got {data[1].get('sale_id')}"


def test_bug_fixed_in_engine():
    assert os.path.isfile(ENGINE), f"Missing file: {ENGINE}"
    with open(ENGINE, "r", encoding="utf-8") as f:
        content = f.read()

    # Retain the original source-level assertion.
    assert "==" in content or "if" in content or "match" in content, "The inner_join method does not seem to have a condition to check for key equality."

    # Exercise the implementation itself with arbitrary key names and unmatched rows.
    spec = importlib.util.spec_from_file_location("audited_pylitecsv_engine", ENGINE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    engine = module.QueryEngine()
    left = [
        {"lk_random": "alpha", "left_value": "L1"},
        {"lk_random": "missing", "left_value": "L2"},
        {"lk_random": "beta", "left_value": "L3"},
    ]
    right = [
        {"rk_random": "beta", "right_value": "R1"},
        {"rk_random": "alpha", "right_value": "R2"},
        {"rk_random": "other", "right_value": "R3"},
    ]
    joined = engine.inner_join(left, right, "lk_random", "rk_random")
    assert joined == [
        {"lk_random": "alpha", "left_value": "L1", "rk_random": "alpha", "right_value": "R2"},
        {"lk_random": "beta", "left_value": "L3", "rk_random": "beta", "right_value": "R1"},
    ], f"inner_join did not enforce equality of the requested keys: {joined}"


def stop_servers():
    subprocess.run(["pkill", "-f", "[s]erver.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.5)


def assert_rows(actual, expected):
    assert len(actual) == len(expected), f"Expected {len(expected)} rows, got {len(actual)}: {actual}"
    for got, want in zip(actual, expected):
        for key, value in want.items():
            assert key in got, f"Merged row is missing column {key!r}: {got}"
            assert str(got[key]) == str(value), f"For column {key!r}, expected {value!r}, got {got[key]!r}"


def test_dynamic_data_general_join_filter_sort_and_pagination():
    sales_path = "/home/user/sales.csv"
    products_path = "/home/user/products.csv"
    with open(sales_path, "rb") as f:
        old_sales = f.read()
    with open(products_path, "rb") as f:
        old_products = f.read()
    with open(ENGINE, "rb") as f:
        old_engine = f.read()

    token = secrets.token_hex(6)
    base = secrets.randbelow(7000) + 2000
    ids = [str(base + i * 17) for i in range(4)]
    cat_a = "CategoryA_" + token
    cat_b = "CategoryB_" + token
    cat_c = "CategoryC_" + token
    products = [
        {"id": ids[0], "name": "Zeta_" + token, "category": cat_a, "price": "31.25"},
        {"id": ids[1], "name": "Alpha_" + token, "category": cat_b, "price": "8.50"},
        {"id": ids[2], "name": "Mu_" + token, "category": cat_a, "price": "72.00"},
        {"id": ids[3], "name": "Beta_" + token, "category": cat_c, "price": "19.75"},
    ]
    sales = [
        {"sale_id": "2", "product_id": ids[0], "amount": "91.10", "date": "2024-03-01"},
        {"sale_id": "11", "product_id": ids[1], "amount": "12.20", "date": "2024-06-03"},
        {"sale_id": "105", "product_id": ids[2], "amount": "77.70", "date": "2024-01-09"},
        {"sale_id": "37", "product_id": ids[0], "amount": "44.40", "date": "2024-07-14"},
        {"sale_id": "8", "product_id": ids[3], "amount": "63.30", "date": "2024-02-11"},
        {"sale_id": "64", "product_id": ids[1], "amount": "25.50", "date": "2024-04-22"},
        {"sale_id": "901", "product_id": str(base + 999), "amount": "999.90", "date": "2024-12-31"},
    ]

    def merged(sale):
        product = next(p for p in products if p["id"] == sale["product_id"])
        return {**sale, **product}

    expected_all = [merged(s) for s in sales if any(p["id"] == s["product_id"] for p in products)]
    audit_log = "/tmp/pylitecsv_calls.log"
    try:
        stop_servers()
        with open(sales_path, "w", encoding="utf-8", newline="") as f:
            f.write("sale_id,product_id,amount,date\n")
            for row in sales:
                f.write(",".join(row[k] for k in ("sale_id", "product_id", "amount", "date")) + "\n")
        with open(products_path, "w", encoding="utf-8", newline="") as f:
            f.write("id,name,category,price\n")
            for row in products:
                f.write(",".join(row[k] for k in ("id", "name", "category", "price")) + "\n")

        # Instrument the required vendored engine before launching server.py. The
        # wrappers preserve behavior while proving that the API actually invokes it.
        instrumentation = r'''
_audit_original_read_csv = QueryEngine.read_csv
_audit_original_inner_join = QueryEngine.inner_join
def _audit_read_csv(self, filepath):
    with open("/tmp/pylitecsv_calls.log", "a", encoding="utf-8") as _f:
        _f.write("read_csv:" + str(filepath) + "\n")
    return _audit_original_read_csv(self, filepath)
def _audit_inner_join(self, left, right, left_key, right_key):
    with open("/tmp/pylitecsv_calls.log", "a", encoding="utf-8") as _f:
        _f.write("inner_join:" + str(left_key) + ":" + str(right_key) + "\n")
    return _audit_original_inner_join(self, left, right, left_key, right_key)
QueryEngine.read_csv = _audit_read_csv
QueryEngine.inner_join = _audit_inner_join
'''
        with open(ENGINE, "ab") as f:
            f.write(("\n" + instrumentation).encode("utf-8"))
        try:
            os.unlink(audit_log)
        except FileNotFoundError:
            pass

        env = os.environ.copy()
        env["PYTHONPATH"] = "/app/pylitecsv-1.0.0" + os.pathsep + env.get("PYTHONPATH", "")
        log = open("/home/user/server.log", "ab", buffering=0)
        subprocess.Popen(
            [sys.executable, SERVER],
            cwd="/home/user",
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        log.close()

        deadline = time.time() + 8
        while time.time() < deadline:
            try:
                if requests.get(URL, timeout=0.5).status_code == 200:
                    break
            except requests.RequestException:
                time.sleep(0.15)
        else:
            pytest.fail("server.py did not start successfully on 127.0.0.1:8000")

        expected = sorted(expected_all, key=lambda r: int(r["sale_id"]))
        assert_rows(get_json({"sort": "sale_id", "order": "asc", "limit": 20, "offset": 0}), expected)

        expected = sorted((r for r in expected_all if r["category"] == cat_a), key=lambda r: float(r["amount"]), reverse=True)[1:3]
        assert_rows(get_json({"category": cat_a, "sort": "amount", "order": "desc", "limit": 2, "offset": 1}), expected)

        expected = sorted((r for r in expected_all if r["category"] == cat_b), key=lambda r: r["date"], reverse=True)
        assert_rows(get_json({"category": cat_b, "sort": "date", "order": "desc", "limit": 10, "offset": 0}), expected)

        assert get_json({"category": "Absent_" + token, "sort": "sale_id", "order": "asc", "limit": 5, "offset": 0}) == []

        with open(audit_log, encoding="utf-8") as f:
            calls = f.read()
        assert "read_csv:" in calls and "sales.csv" in calls and "products.csv" in calls, "The API did not use pylitecsv.QueryEngine.read_csv for both CSV files"
        assert "inner_join:product_id:id" in calls, "The API did not use pylitecsv.QueryEngine.inner_join with product_id and id"
    finally:
        stop_servers()
        with open(sales_path, "wb") as f:
            f.write(old_sales)
        with open(products_path, "wb") as f:
            f.write(old_products)
        with open(ENGINE, "wb") as f:
            f.write(old_engine)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
