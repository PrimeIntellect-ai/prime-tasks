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
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import types
import uuid

import pytest
import requests

REPO = "/app/anomaly_pipeline/worker_repo"
EXPECTED_VARIANCE = 1.0
for _ in range(1000):
    EXPECTED_VARIANCE += 0.001


def git(*args, check=True):
    return subprocess.run(
        ["git", "-C", REPO, *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def commit_is_good(commit):
    with tempfile.TemporaryDirectory() as td:
        for name in ("compute_engine.py", "test_convergence.py"):
            result = git("show", f"{commit}:{name}", check=False)
            if result.returncode != 0:
                return False
            with open(os.path.join(td, name), "w") as f:
                f.write(result.stdout)
        result = subprocess.run(
            [sys.executable, "test_convergence.py"],
            cwd=td,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.returncode == 0


def derive_first_bad_commit():
    assert git("merge-base", "--is-ancestor", "v1.0", "HEAD", check=False).returncode == 0, \
        "v1.0 is not an ancestor of HEAD"
    assert commit_is_good("v1.0"), "The tagged good revision v1.0 no longer passes"

    commits = git("rev-list", "--reverse", "--ancestry-path", "v1.0..HEAD").stdout.splitlines()
    first_bad = None
    for commit in commits:
        if not commit_is_good(commit):
            first_bad = commit
            break
    assert first_bad is not None, "No regression-introducing commit was found in the v1.0..HEAD history"
    return first_bad


def test_bad_commit_txt():
    path = "/home/user/bad_commit.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    supplied = open(path).read().strip()
    assert re.fullmatch(r"[0-9a-f]{40}", supplied), "bad_commit.txt must contain a full 40-character hash"
    assert git("cat-file", "-e", f"{supplied}^{{commit}}", check=False).returncode == 0, \
        "bad_commit.txt does not identify a commit in the repository"
    assert supplied == derive_first_bad_commit(), "bad_commit.txt does not contain the first bad commit"


def test_fix_is_committed_on_main():
    assert git("branch", "--show-current").stdout.strip() == "main", "The fix is not checked out on main"
    assert git("diff", "--quiet", "HEAD", "--", "compute_engine.py", check=False).returncode == 0, \
        "compute_engine.py has uncommitted changes"
    bad = open("/home/user/bad_commit.txt").read().strip()
    assert git("merge-base", "--is-ancestor", bad, "HEAD", check=False).returncode == 0, \
        "The fix commit is not a descendant of the regression"
    assert git("rev-parse", "HEAD").stdout.strip() != bad, "No fix was committed after the bad commit"


def test_compute_engine_float64_iterations_and_result():
    path = os.path.join(REPO, "compute_engine.py")
    assert os.path.isfile(path), "compute_engine.py is missing"
    source = open(path).read()
    tree = ast.parse(source)
    funcs = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "compute_variance"]
    assert len(funcs) == 1, "compute_variance must be defined exactly once"
    assert not any(isinstance(n, ast.Attribute) and n.attr == "float32" for n in ast.walk(funcs[0])), \
        "compute_variance still uses float32"

    counters = {"float64": 0, "adds": 0}

    class Scalar:
        def __init__(self, value):
            self.value = float(value.value if isinstance(value, Scalar) else value)

        def __iadd__(self, other):
            counters["adds"] += 1
            self.value += float(other)
            return self

        def __float__(self):
            return self.value

    fake_numpy = types.ModuleType("numpy")

    def float64(value):
        counters["float64"] += 1
        return Scalar(value)

    def float32(value):
        raise AssertionError("compute_variance invoked float32")

    fake_numpy.float64 = float64
    fake_numpy.float32 = float32
    previous = sys.modules.get("numpy")
    sys.modules["numpy"] = fake_numpy
    try:
        namespace = {}
        exec(compile(source, path, "exec"), namespace)
        result = namespace["compute_variance"]()
    finally:
        if previous is None:
            sys.modules.pop("numpy", None)
        else:
            sys.modules["numpy"] = previous

    assert counters["float64"] == 1001, "compute_variance must perform all values in float64"
    assert counters["adds"] == 1000, "compute_variance must execute 1000 iterative updates"
    assert math.isclose(float(result), EXPECTED_VARIANCE, rel_tol=0, abs_tol=1e-12)

    convergence = subprocess.run(
        [sys.executable, "test_convergence.py"], cwd=REPO,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert convergence.returncode == 0, f"test_convergence.py failed: {convergence.stdout}{convergence.stderr}"


def test_config_json_port():
    path = "/app/anomaly_pipeline/config.json"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path) as f:
        config = json.load(f)
    assert config.get("redis_port") == 6379, "redis_port in config.json is not 6379."


def assert_correct_response(data):
    assert data.get("status") == "converged", f"Expected status 'converged', got {data.get('status')}."
    assert "variance" in data, "API response missing 'variance'."
    assert isinstance(data["variance"], (float, int)) and not isinstance(data["variance"], bool), \
        "API response 'variance' is not a number."
    assert math.isclose(float(data["variance"]), EXPECTED_VARIANCE, rel_tol=0, abs_tol=1e-12), \
        f"Incorrect variance: {data['variance']}"


def test_api_response_json():
    path = "/home/user/api_response.json"
    assert os.path.isfile(path), f"File {path} does not exist."
    try:
        with open(path) as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {path} does not contain valid JSON.")
    assert "status" in data, "API response JSON missing 'status' key."
    assert_correct_response(data)


def test_api_endpoint():
    url = "http://127.0.0.1:8080/api/v1/analyze"
    headers = {"Authorization": "Bearer IT-SUPPORT-AUTH-992"}

    unauthorized = requests.post(url, json={"series_id": f"unauth_{uuid.uuid4().hex}"}, timeout=10)
    assert unauthorized.status_code == 401, "The API did not enforce the required Bearer token"

    for _ in range(3):
        payload = {"series_id": f"verify_{uuid.uuid4().hex}"}
        try:
            response = requests.post(url, json=payload, headers=headers, timeout=10)
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to API: {e}")
        assert response.status_code == 200, \
            f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"API response is not valid JSON. Response: {response.text}")
        assert_correct_response(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
