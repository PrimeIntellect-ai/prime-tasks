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
import concurrent.futures
import importlib.util
import inspect
import math
import os
from pathlib import Path
import random
import subprocess
import sys
import threading
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
HEADERS = {"Authorization": "Bearer calc-token-998"}
REPO = Path("/home/user/math-service")
VENDORED_CORE = Path("/app/vendored/fast-variance/fast_variance/core.py")

ORIGINAL_CORE = '''class VarianceCalculator:
    _scratch_pad = []

    def calculate(self, data):
        self._scratch_pad.clear()
        if not data: return 0.0
        mean = sum(data) / len(data)
        for x in data:
            self._scratch_pad.append((x - mean) ** 2)
        return sum(self._scratch_pad) / len(data)
'''


def wait_for_service():
    """Wait for the service to be available."""
    for _ in range(10):
        try:
            resp = requests.post(f"{BASE_URL}/sum", json={"data": []}, timeout=1)
            if resp.status_code in [401, 403, 422, 200]:
                return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)
    return False


@pytest.fixture(scope="module", autouse=True)
def ensure_service_running():
    assert wait_for_service(), f"Service is not reachable at {BASE_URL}"


def post(endpoint, data, timeout=15):
    return requests.post(
        f"{BASE_URL}/{endpoint}", json={"data": data}, headers=HEADERS, timeout=timeout
    )


def population_variance(data):
    if not data:
        return 0.0
    mean = math.fsum(data) / len(data)
    return math.fsum((x - mean) ** 2 for x in data) / len(data)


def git(*args):
    return subprocess.check_output(
        ["git", "-c", f"safe.directory={REPO}", "-C", str(REPO), *args]
    )


def test_git_repair_is_present():
    """The checked-out service must actually differ from the regression commit."""
    assert (REPO / ".git").is_dir(), "math-service is no longer a Git repository"
    assert (REPO / "app.py").is_file(), "app.py is missing"

    lines = git("log", "--all", "--format=%H%x09%s").decode().splitlines()
    regression_commits = [line.split("\t", 1)[0] for line in lines if line.endswith("\tOptimize sum")]
    assert regression_commits, "The supplied regression commit is missing from Git history"

    regressed_app = git("show", f"{regression_commits[0]}:app.py")
    current_app = (REPO / "app.py").read_bytes()
    assert current_app != regressed_app, "app.py is still identical to the precision-regression version"


def test_vendored_package_was_repaired_and_installed():
    """Exercise both the vendored source and the package imported by the service environment."""
    assert VENDORED_CORE.is_file(), "Vendored fast-variance source is missing"
    source = VENDORED_CORE.read_text()
    assert source != ORIGINAL_CORE, "Vendored fast-variance source is still the original racy implementation"

    spec = importlib.util.spec_from_file_location("verifier_vendored_core", VENDORED_CORE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    from fast_variance import VarianceCalculator as InstalledCalculator

    installed_file = Path(inspect.getfile(InstalledCalculator)).resolve()
    assert installed_file.is_file(), "Installed fast-variance implementation cannot be located"

    exercise_calculator_concurrently(module.VarianceCalculator)
    exercise_calculator_concurrently(InstalledCalculator)


def exercise_calculator_concurrently(calculator_class):
    workers = 20
    barrier = threading.Barrier(workers)
    datasets = []
    for i in range(workers):
        scale = float(i + 1)
        length = 10000 + i * 17
        datasets.append([scale * ((j % 13) - 6) for j in range(length)])

    expected = [population_variance(data) for data in datasets]
    old_interval = sys.getswitchinterval()
    sys.setswitchinterval(1e-6)
    try:
        def run(i):
            barrier.wait(timeout=10)
            values = []
            for _ in range(3):
                values.append(calculator_class().calculate(datasets[i]))
            return i, values

        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
            results = list(executor.map(run, range(workers)))
    finally:
        sys.setswitchinterval(old_interval)

    for i, values in results:
        for value in values:
            assert math.isclose(value, expected[i], rel_tol=1e-10, abs_tol=1e-10), (
                f"VarianceCalculator produced {value} instead of {expected[i]} under concurrency"
            )


def test_unauthorized_access():
    """Test that missing or incorrect token returns 401."""
    resp_missing = requests.post(f"{BASE_URL}/sum", json={"data": [1.0, 2.0]})
    assert resp_missing.status_code in [401, 403], f"Expected 401/403 for missing token, got {resp_missing.status_code}"

    resp_invalid = requests.post(
        f"{BASE_URL}/sum",
        json={"data": [1.0, 2.0]},
        headers={"Authorization": "Bearer invalid-token"},
    )
    assert resp_invalid.status_code in [401, 403], f"Expected 401/403 for invalid token, got {resp_invalid.status_code}"


def test_sum_precision():
    """Retain the original catastrophic-cancellation assertion."""
    data = {"data": [1e16, 1.0, -1e16]}
    resp = requests.post(f"{BASE_URL}/sum", json=data, headers=HEADERS)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}: {resp.text}"

    result = resp.json().get("result")
    assert result is not None, "Response JSON missing 'result' key"
    assert result == 1.0, f"Expected sum result 1.0, got {result}. Precision bug not fixed."


def test_sum_precision_on_unpredictable_inputs():
    """Compare additional, runtime-generated cancellation cases with math.fsum."""
    rng = random.SystemRandom()
    cases = []
    for _ in range(10):
        values = []
        for _ in range(rng.randrange(8, 18)):
            large = float(rng.randrange(10**14, 10**16))
            small = rng.randrange(-2000, 2001) / 4.0
            values.extend([large, small, -large])
        rng.shuffle(values)
        cases.append(values)

    for values in cases:
        expected = math.fsum(values)
        resp = post("sum", values)
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert "result" in body
        actual = body["result"]
        assert isinstance(actual, (int, float)) and math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=2e-15, abs_tol=1e-9), (
            f"Inaccurate sum for generated input: expected {expected}, got {actual}"
        )


def test_variance_concurrency():
    """Retain the original fixed-payload concurrent assertion."""
    payload = {"data": [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]}

    def make_request():
        resp = requests.post(f"{BASE_URL}/variance", json=payload, headers=HEADERS)
        if resp.status_code != 200:
            return None, resp.status_code
        return resp.json().get("result"), resp.status_code

    num_requests = 50
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        futures = [executor.submit(make_request) for _ in range(num_requests)]
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())

    for val, status in results:
        assert status == 200, f"Expected 200 OK during concurrent requests, got {status}"
        assert val is not None, "Response JSON missing 'result' key during concurrent requests"
        assert abs(val - 4.0) < 1e-7, f"Expected variance 4.0, got {val}. Concurrency bug not fixed."


def test_variance_concurrency_on_distinct_inputs():
    """Concurrent requests use different generated payloads and independently derived answers."""
    workers = 32
    barrier = threading.Barrier(workers)
    nonce = int.from_bytes(os.urandom(4), "big")
    payloads = []
    for i in range(workers):
        scale = float(1 + ((nonce + i * 17) % 41)) / 3.0
        length = 2500 + i * 7
        payloads.append([scale * ((j % 17) - 8) for j in range(length)])
    expected = [population_variance(data) for data in payloads]

    def make_request(i):
        barrier.wait(timeout=10)
        resp = post("variance", payloads[i], timeout=30)
        return i, resp

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        results = list(executor.map(make_request, range(workers)))

    for i, resp in results:
        assert resp.status_code == 200, f"Concurrent variance request failed: {resp.status_code} {resp.text}"
        body = resp.json()
        assert "result" in body
        actual = body["result"]
        assert math.isclose(actual, expected[i], rel_tol=1e-9, abs_tol=1e-8), (
            f"Concurrent variance mismatch: expected {expected[i]}, got {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
