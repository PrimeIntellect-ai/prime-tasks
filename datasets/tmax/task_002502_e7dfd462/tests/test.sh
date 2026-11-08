#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import socket
import statistics
import subprocess
import threading
import time
import urllib.error
import urllib.request

import pytest

FIXED_SERVICE_PATH = "/home/user/fixed_math_service.py"
PORT = 8080
URL = f"http://127.0.0.1:{PORT}"


@pytest.fixture
def server_process():
    assert os.path.exists(FIXED_SERVICE_PATH), f"File {FIXED_SERVICE_PATH} not found."
    assert os.path.isfile(FIXED_SERVICE_PATH), f"{FIXED_SERVICE_PATH} is not a file."

    proc = subprocess.Popen(
        ["python3", FIXED_SERVICE_PATH],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    started = False
    for _ in range(50):
        if proc.poll() is not None:
            break
        try:
            with socket.create_connection(("127.0.0.1", PORT), timeout=0.2):
                started = True
                break
        except OSError:
            time.sleep(0.1)

    if not started or proc.poll() is not None:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=2)
        pytest.fail("Server did not start or become reachable on port 8080.")

    yield proc

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def send_request(data):
    req = urllib.request.Request(
        URL,
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    response = urllib.request.urlopen(req, timeout=5)
    assert response.status == 200
    return json.loads(response.read().decode())


def assert_correct_std_dev(response, all_values):
    assert "std_dev" in response, "Response missing 'std_dev' key."
    std_dev = response["std_dev"]
    assert isinstance(std_dev, (int, float)) and not isinstance(std_dev, bool), \
        "'std_dev' must be numeric."
    assert not math.isnan(std_dev), "Calculated standard deviation is NaN."
    assert math.isfinite(std_dev), "Calculated standard deviation is not finite."

    parsed = [float(v.replace(",", "")) if isinstance(v, str) else float(v)
              for v in all_values]
    expected = statistics.pstdev(parsed)
    assert math.isclose(float(std_dev), expected, rel_tol=1e-6, abs_tol=1e-8), \
        f"Incorrect standard deviation: got {std_dev}, expected {expected}."


def test_numerical_instability(server_process):
    values = ["100000000.01", "100000000.02"]
    try:
        res = send_request({"values": values})
        assert "std_dev" in res, "Response missing 'std_dev' key."
        std_dev = res["std_dev"]
        assert not math.isnan(std_dev), "Calculated standard deviation is NaN."
        assert_correct_std_dev(res, values)
    except urllib.error.HTTPError as e:
        pytest.fail(f"Server returned HTTP {e.code} for close large values. Math domain error likely occurred.")
    except Exception as e:
        pytest.fail(f"Request failed: {e}")


def test_comma_parsing(server_process):
    values = ["1,000.5", "2,000.5"]
    try:
        res = send_request({"values": values})
        assert "std_dev" in res, "Response missing 'std_dev' key."
        assert_correct_std_dev(res, values)
    except urllib.error.HTTPError as e:
        pytest.fail(f"Server returned HTTP {e.code} for comma-separated values. Parsing failed.")
    except Exception as e:
        pytest.fail(f"Request failed: {e}")


def test_concurrency(server_process):
    errors = []
    errors_lock = threading.Lock()
    workers = 20
    requests_per_worker = 10
    barrier = threading.Barrier(workers)

    def worker():
        try:
            barrier.wait(timeout=5)
            for _ in range(requests_per_worker):
                res = send_request({"values": [1, 2, 3]})
                assert "std_dev" in res, "Response missing 'std_dev' key."
        except Exception as e:
            with errors_lock:
                errors.append(e)

    threads = []
    for _ in range(workers):
        t = threading.Thread(target=worker)
        threads.append(t)
        t.start()

    for t in threads:
        t.join(timeout=30)

    assert all(not t.is_alive() for t in threads), "Concurrency test timed out."
    assert not errors, f"Concurrency test encountered errors: {errors[0]}"

    try:
        res = send_request({"values": [4, 5, 6]})
        assert "std_dev" in res, "Response missing 'std_dev' key."
        accumulated = [1, 2, 3] * (workers * requests_per_worker) + [4, 5, 6]
        assert_correct_std_dev(res, accumulated)
    except Exception as e:
        pytest.fail(f"Server failed to respond correctly after concurrent load: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
