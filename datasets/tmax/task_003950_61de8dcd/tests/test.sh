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
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import socket
import subprocess
import time

import pytest
import requests

TARGET = "/home/user/dataset-catalog"
URL = "http://127.0.0.1:9090/score"


def test_target_directory_exists():
    """Verify that the target directory exists."""
    assert os.path.isdir(TARGET), f"Target directory {TARGET} does not exist. Did you copy the package?"


def test_scorer_bayes_go_fixed():
    """Preserve the source-level assertion from the original verifier."""
    path = os.path.join(TARGET, "scorer", "bayes.go")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "(prior * likelihood)" in content or "prior*likelihood" in content or "prior * likelihood" in content, \
        "The mathematical bug in bayes.go does not appear to be fixed."


def test_randomized_scorer_and_required_tests_benchmarks():
    """Directly exercise CalculatePosterior on unpredictable inputs, then run the required command."""
    rng = secrets.SystemRandom()
    cases = []
    for _ in range(16):
        prior = rng.uniform(0.01, 0.99)
        likelihood = rng.uniform(0.01, 0.99)
        marginal = rng.uniform(0.05, 1.0)
        cases.append((prior, likelihood, marginal, (prior * likelihood) / marginal))

    rows = "\n".join(
        "        {%s, %s, %s, %s}," % tuple(format(v, ".17g") for v in case)
        for case in cases
    )
    test_source = f'''package scorer

import (
    "math"
    "testing"
)

func TestVerifierRandomPosteriorCases(t *testing.T) {{
    cases := []struct {{ prior, likelihood, marginal, want float64 }}{{
{rows}
    }}
    for _, tc := range cases {{
        got := CalculatePosterior(tc.prior, tc.likelihood, tc.marginal)
        tolerance := 1e-12 * math.Max(1, math.Abs(tc.want))
        if math.IsNaN(got) || math.IsInf(got, 0) || math.Abs(got-tc.want) > tolerance {{
            t.Fatalf("CalculatePosterior(%g, %g, %g) = %.17g; want %.17g", tc.prior, tc.likelihood, tc.marginal, got, tc.want)
        }}
    }}
}}
'''
    test_path = os.path.join(TARGET, "scorer", f"verifier_{secrets.token_hex(8)}_test.go")
    try:
        with open(test_path, "w", encoding="utf-8") as f:
            f.write(test_source)
        result = subprocess.run(
            ["go", "test", "-bench", ".", "./..."],
            cwd=TARGET,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
        )
        assert result.returncode == 0, "go test -bench . ./... failed:\n" + result.stdout
    finally:
        try:
            os.remove(test_path)
        except FileNotFoundError:
            pass


@pytest.fixture(scope="session")
def independently_built_service():
    """Build the submitted Go application and run that build on an isolated port."""
    binary = f"/tmp/dataset-catalog-verifier-{secrets.token_hex(8)}"
    build = subprocess.run(
        ["go", "build", "-o", binary, "."],
        cwd=TARGET,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert build.returncode == 0, "Go application did not build:\n" + build.stdout
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Build did not produce an executable"

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    env = os.environ.copy()
    env["PORT"] = str(port)
    process = subprocess.Popen(
        [binary], cwd=TARGET, env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    url = f"http://127.0.0.1:{port}/score"
    try:
        deadline = time.time() + 8
        while time.time() < deadline:
            if process.poll() is not None:
                pytest.fail("The independently built Go service exited before accepting requests")
            try:
                requests.get(url, params={"prior": 0.5, "likelihood": 0.5, "marginal": 0.5}, timeout=0.25)
                break
            except requests.RequestException:
                time.sleep(0.1)
        else:
            pytest.fail("The independently built Go service did not start listening")
        yield url
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        try:
            os.remove(binary)
        except FileNotFoundError:
            pass


def assert_score(url, prior, likelihood, marginal):
    response = requests.get(
        url,
        params={"prior": prior, "likelihood": likelihood, "marginal": marginal},
        timeout=2,
    )
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert "posterior" in data, f"Expected 'posterior' in JSON response, got {data}"
    assert isinstance(data["posterior"], (int, float)) and math.isfinite(data["posterior"])
    expected = (prior * likelihood) / marginal
    assert math.isclose(data["posterior"], expected, rel_tol=1e-10, abs_tol=1e-12), \
        f"Expected posterior {expected}, got {data['posterior']}"


def test_service_running_and_correct():
    """Preserve both original protocol checks against the required live service."""
    try:
        assert_score(URL, 0.4, 0.8, 0.5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}. Is it running in the background? Error: {e}")
    assert_score(URL, 0.3, 0.6, 0.9)


def test_live_and_built_services_on_unpredictable_inputs(independently_built_service):
    """Prevent fixed-response services and verify the built submitted artifact over HTTP."""
    rng = secrets.SystemRandom()
    for _ in range(12):
        prior = rng.uniform(0.01, 0.99)
        likelihood = rng.uniform(0.01, 0.99)
        marginal = rng.uniform(0.05, 1.0)
        assert_score(URL, prior, likelihood, marginal)
        assert_score(independently_built_service, prior, likelihood, marginal)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
