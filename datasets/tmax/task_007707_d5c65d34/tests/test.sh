#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import socket
import stat
import subprocess
import urllib.error
import urllib.request

import pytest

REPO_DIR = "/home/user/math-api"
SCRIPT_PATH = "/home/user/verify.sh"
OUTPUT_FILE = "/home/user/api_output.json"


def population_variance(values):
    if not values:
        return 0.0
    mean = sum(values) / len(values)
    return sum((value - mean) ** 2 for value in values) / len(values)


def post_variance(values):
    request = urllib.request.Request(
        "http://localhost:8080/variance",
        data=json.dumps({"numbers": values}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            assert response.status == 200, f"Unexpected HTTP status: {response.status}"
            body = response.read().decode("utf-8")
    except (urllib.error.URLError, TimeoutError) as exc:
        pytest.fail(f"API server is not reachable on localhost:8080: {exc}")

    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        pytest.fail(f"API returned invalid JSON {body!r}: {exc}")

    assert isinstance(payload, dict), f"API response is not an object: {payload!r}"
    assert set(payload) == {"variance"}, f"API response has the wrong shape: {payload!r}"
    assert isinstance(payload["variance"], (int, float)) and not isinstance(payload["variance"], bool)
    return float(payload["variance"])


def test_go_tests_pass():
    """Verify that all checked-in Go tests pass."""
    assert os.path.isdir(REPO_DIR), f"Repository directory {REPO_DIR} is missing."
    result = subprocess.run(
        ["go", "test", "./..."],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Go tests failed:\n{result.stdout}\n{result.stderr}"


def test_calculate_variance_on_derived_inputs():
    """Execute CalculateVariance on fresh inputs and independently derived answers."""
    rng = random.SystemRandom()
    cases = [
        [],
        [rng.uniform(-100, 100)],
        [rng.uniform(-100, 100) for _ in range(2)],
        [rng.uniform(-1000, 1000) for _ in range(7)],
        [rng.uniform(-10, 10) for _ in range(13)],
    ]

    case_lines = []
    for values in cases:
        go_values = ", ".join(format(value, ".17g") for value in values)
        expected = population_variance(values)
        case_lines.append(
            "{data: []float64{%s}, expected: %.17g}" % (go_values, expected)
        )

    generated_test = """package main

import (
    "math"
    "testing"
)

func TestVerifierPopulationVariance(t *testing.T) {
    cases := []struct {
        data []float64
        expected float64
    }{
        %s,
    }
    for _, tc := range cases {
        got := CalculateVariance(tc.data)
        tolerance := 1e-9 * math.Max(1, math.Abs(tc.expected))
        if math.Abs(got-tc.expected) > tolerance {
            t.Fatalf("CalculateVariance(%%v) = %%.17g; expected %%.17g", tc.data, got, tc.expected)
        }
    }
}
""" % (",\n        ".join(case_lines))

    test_path = os.path.join(REPO_DIR, "zz_verifier_population_variance_test.go")
    with open(test_path, "w", encoding="utf-8") as handle:
        handle.write(generated_test)
    try:
        result = subprocess.run(
            ["go", "test", "-count=1", "./..."],
            cwd=REPO_DIR,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, (
            f"CalculateVariance failed derived population-variance cases:\n"
            f"{result.stdout}\n{result.stderr}"
        )
    finally:
        if os.path.exists(test_path):
            os.remove(test_path)


def test_dependencies_fixed():
    """Verify that go.mod contains the new chi dependency."""
    go_mod = os.path.join(REPO_DIR, "go.mod")
    assert os.path.isfile(go_mod), f"go.mod missing at {go_mod}."
    with open(go_mod, "r", encoding="utf-8") as handle:
        content = handle.read()
    assert "github.com/go-chi/chi/v5" in content, (
        "go.mod does not contain the github.com/go-chi/chi/v5 dependency."
    )


def test_stats_go_fixed():
    """Retain the source-level check that sample division was removed."""
    stats_go = os.path.join(REPO_DIR, "stats.go")
    assert os.path.isfile(stats_go), f"stats.go missing at {stats_go}."
    with open(stats_go, "r", encoding="utf-8") as handle:
        content = handle.read()
    assert "len(data)-1" not in content.replace(" ", ""), (
        "stats.go still contains sample variance division (len(data)-1)."
    )
    assert "float64(len(data))" in content, (
        "stats.go does not seem to divide by float64(len(data))."
    )


def test_verify_script_exists_and_executable():
    """Verify that verify.sh exists, is executable, and invokes curl."""
    assert os.path.isfile(SCRIPT_PATH), f"verify.sh missing at {SCRIPT_PATH}."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert bool(mode & stat.S_IXUSR), f"{SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as handle:
        script = handle.read()
    non_comment_lines = "\n".join(
        line for line in script.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"(^|[;&|[:space:]])curl([[:space:]]|$)", non_comment_lines), (
        "verify.sh does not invoke curl."
    )


def test_project_builds_and_running_api_handles_derived_inputs():
    """Build the submitted server and exercise the already-running API on fresh inputs."""
    build = subprocess.run(
        ["go", "build", "-o", "/tmp/math-api-verifier", "."],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, f"Go build failed:\n{build.stdout}\n{build.stderr}"

    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=2):
            pass
    except OSError as exc:
        pytest.fail(f"API server was not left running on port 8080: {exc}")

    rng = random.SystemRandom()
    cases = [
        [rng.uniform(-500, 500) for _ in range(3)],
        [rng.uniform(-50, 50) for _ in range(8)],
        [rng.uniform(-5, 5) for _ in range(11)],
    ]
    for values in cases:
        expected = population_variance(values)
        actual = post_variance(values)
        tolerance = 1e-9 * max(1.0, abs(expected))
        assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=tolerance), (
            f"For {values!r}, expected population variance {expected}, got {actual}"
        )


def test_verify_script_generates_strict_correct_output():
    """Run verify.sh and validate its freshly generated output exactly."""
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"verify.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

    with open(OUTPUT_FILE, "r", encoding="utf-8") as handle:
        raw = handle.read()
    assert re.fullmatch(
        r'\{"variance":-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\}\n?', raw
    ), f"Output does not strictly match {{\"variance\":<value>}}: {raw!r}"

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"File {OUTPUT_FILE} does not contain valid JSON.")
    assert set(data) == {"variance"}, f"JSON output has the wrong keys: {data}"
    assert isinstance(data["variance"], (int, float)) and not isinstance(data["variance"], bool)

    expected = population_variance([10.5, 20.0, 30.5, 40.0])
    assert abs(float(data["variance"]) - expected) < 1e-6, (
        f"Expected population variance {expected}, got {data['variance']}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
