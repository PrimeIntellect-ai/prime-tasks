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
import csv
import math
import os
import re
import secrets
import stat
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/search"


def embed(text):
    output = subprocess.check_output(["/app/embedder", text], text=True, timeout=5).strip()
    values = [float(x) for x in output.split(",")]
    assert len(values) == 64, "Embedder did not return a 64-dimensional vector"
    return values


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb)


def cleaned_products():
    with open("/home/user/products.csv", newline="") as f:
        products = list(csv.DictReader(f))
    with open("/home/user/prices.csv", newline="") as f:
        prices = {row["product_id"]: row.get("price", "") for row in csv.DictReader(f)}

    result = []
    for row in products:
        description = row.get("description", "")
        raw_price = prices.get(row.get("product_id", ""), "")
        if not description.strip() or not raw_price.strip():
            continue
        try:
            price = float(raw_price)
        except ValueError:
            continue
        if price < 0:
            continue
        result.append((row["product_id"], description))
    return result


def wait_for_server():
    response = None
    for _ in range(5):
        try:
            response = requests.post(
                URL,
                json={"query": "High quality wireless mouse", "k": 1},
                timeout=2,
            )
            if response.status_code == 200:
                return response
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)
    pytest.fail("Server is not running or not responding on 127.0.0.1:8080")


def assert_result_shape(item):
    assert isinstance(item, dict), "Each result must be a JSON object"
    assert "product_id" in item, "Result missing 'product_id'"
    assert "score" in item, "Result missing 'score'"
    assert isinstance(item["product_id"], str)
    assert isinstance(item["score"], (int, float)) and not isinstance(item["score"], bool)
    assert math.isfinite(float(item["score"]))


def test_files_exist_and_go_source_builds():
    expected_files = [
        "/home/user/server.go",
        "/home/user/benchmark.sh",
        "/home/user/benchmark_results.txt",
    ]
    for path in expected_files:
        assert os.path.isfile(path), f"Expected file missing: {path}"

    subprocess.run(
        ["go", "build", "-o", "/tmp/submitted-server", "/home/user/server.go"],
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_server_running_and_search_endpoint():
    response = wait_for_server()
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"

    data = response.json()
    assert isinstance(data, list), "Response should be a JSON array"
    assert len(data) == 1, "Expected exactly 1 result for k=1"

    top_result = data[0]
    assert_result_shape(top_result)
    assert top_result["product_id"] == "P001", "Expected P001 as top result for its own description"
    assert abs(float(top_result["score"]) - 1.0) <= 2e-5, "Incorrect cosine score for exact P001 description"


def test_search_endpoint_p004():
    try:
        response = requests.post(
            URL,
            json={"query": "Noise cancelling bluetooth headphones", "k": 2},
            timeout=2,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    data = response.json()
    assert isinstance(data, list), "Response should be a JSON array"
    assert len(data) <= 2, "Expected at most 2 results for k=2"
    assert len(data) > 0, "Expected at least 1 result"
    for item in data:
        assert_result_shape(item)

    assert data[0]["product_id"] == "P004", "Expected P004 as top result for its own description"
    assert abs(float(data[0]["score"]) - 1.0) <= 2e-5, "Incorrect cosine score for exact P004 description"

    product_ids = [item["product_id"] for item in data]
    for invalid_id in ["P002", "P003", "P005"]:
        assert invalid_id not in product_ids, f"Cleaned dataset should not contain {invalid_id}"


def test_dynamic_queries_embedder_use_scores_and_benchmark():
    products = cleaned_products()
    assert products, "The cleaned fixture unexpectedly has no products"
    product_vectors = {pid: embed(description) for pid, description in products}

    # These queries are generated only after the agent has finished, so fixed responses cannot pass.
    queries = [
        "verifier dynamic query " + secrets.token_hex(16)
        for _ in range(4)
    ]
    query_vectors = {query: embed(query) for query in queries}
    expected = {}
    for query in queries:
        ranked = sorted(
            ((pid, cosine(query_vectors[query], product_vectors[pid])) for pid, _ in products),
            key=lambda item: item[1],
            reverse=True,
        )
        expected[query] = ranked

    real_embedder = "/app/embedder.verifier-real"
    call_log = "/tmp/verifier_embedder_calls"
    assert not os.path.exists(real_embedder), "Unexpected stale verifier embedder file"
    try:
        os.rename("/app/embedder", real_embedder)
        with open("/app/embedder", "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\n' \"$1\" >> /tmp/verifier_embedder_calls\nexec /app/embedder.verifier-real \"$@\"\n")
        os.chmod("/app/embedder", stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        open(call_log, "w").close()
        os.chmod(call_log, 0o666)

        k = len(products)
        for query in queries:
            response = requests.post(URL, json={"query": query, "k": k}, timeout=5)
            assert response.status_code == 200
            data = response.json()
            assert isinstance(data, list)
            assert len(data) == k, f"Expected exactly {k} cleaned products"
            for actual, (expected_id, expected_score) in zip(data, expected[query]):
                assert_result_shape(actual)
                assert actual["product_id"] == expected_id, "Results are not ordered by cosine similarity"
                assert abs(float(actual["score"]) - expected_score) <= 2e-5, "Returned cosine score is incorrect"

        with open(call_log) as f:
            calls = f.read().splitlines()
        for query in queries:
            assert query in calls, "The running server did not invoke /app/embedder for a query"

        # Run the submitted benchmark again while embedder invocations are observable.
        open(call_log, "w").close()
        before = time.time_ns()
        completed = subprocess.run(
            ["bash", "/home/user/benchmark.sh"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert completed.returncode == 0, f"benchmark.sh failed: {completed.stderr}"
        results_path = "/home/user/benchmark_results.txt"
        assert os.path.isfile(results_path)
        assert os.stat(results_path).st_mtime_ns >= before, "benchmark_results.txt was not regenerated"
        with open(results_path, errors="replace") as f:
            benchmark_output = f.read()
        assert benchmark_output.strip(), "benchmark_results.txt is empty"

        with open(call_log) as f:
            benchmark_calls = f.read().splitlines()
        assert len(benchmark_calls) >= 100, "benchmark.sh did not send 100 requests through /search"

        lower = benchmark_output.lower()
        ab_complete = re.search(r"complete requests:\s*(\d+)", lower)
        hey_success = re.search(r"\[200\]\s*(\d+)\s+responses", lower)
        if ab_complete:
            assert int(ab_complete.group(1)) == 100, "ab output does not report 100 completed requests"
            failed = re.search(r"failed requests:\s*(\d+)", lower)
            assert failed and int(failed.group(1)) == 0, "ab reported failed requests"
        elif hey_success:
            assert int(hey_success.group(1)) == 100, "hey output does not report 100 successful responses"
        else:
            pytest.fail("benchmark_results.txt is not genuine successful hey/ab benchmark output")
    finally:
        if os.path.exists("/app/embedder") and os.path.exists(real_embedder):
            os.unlink("/app/embedder")
        if os.path.exists(real_embedder):
            os.rename(real_embedder, "/app/embedder")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
