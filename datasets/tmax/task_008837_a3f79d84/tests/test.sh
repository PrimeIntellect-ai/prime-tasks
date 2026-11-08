#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import tempfile
import pytest

WORKSPACE = "/home/user/workspace"
MAIN_PATH = os.path.join(WORKSPACE, "main.go")
GO_MOD_PATH = os.path.join(WORKSPACE, "go.mod")
RESULTS_PATH = os.path.join(WORKSPACE, "results.json")


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def test_program_exists_builds_and_runs():
    assert os.path.isfile(MAIN_PATH), f"File {MAIN_PATH} does not exist."
    assert os.path.isfile(GO_MOD_PATH), f"File {GO_MOD_PATH} does not exist."

    module_name = run(["go", "list", "-m"], cwd=WORKSPACE).stdout.strip()
    assert module_name == "analyzer", f"Expected Go module analyzer, got {module_name!r}"

    sources = []
    for name in os.listdir(WORKSPACE):
        if name.endswith(".go") and os.path.isfile(os.path.join(WORKSPACE, name)):
            with open(os.path.join(WORKSPACE, name), "r", encoding="utf-8") as f:
                sources.append(f.read())
    source = "\n".join(sources)
    assert '"math"' in source, "Go source must use the math package."
    assert re.search(r"\.\s*Exp\s*\(", source), "Go source must evaluate the exponential."
    assert re.search(r"\.\s*Sin\s*\(", source), "Go source must evaluate the sine."
    assert '"math/rand"' in source, "Go source must use math/rand."
    assert re.search(r"\.\s*Seed\s*\(\s*42\s*\)", source), "Go source must seed math/rand with 42."
    assert re.search(r"\.\s*NormFloat64\s*\(", source), "Go source must generate Gaussian noise."
    assert re.search(r"\bfor\b", source), "Go source must perform iterative numerical work."

    executable = os.path.join(tempfile.gettempdir(), "submitted-analyzer")
    if os.path.exists(executable):
        os.remove(executable)
    run(["go", "build", "-o", executable, "."], cwd=WORKSPACE, timeout=60)
    assert os.path.isfile(executable), "go build did not produce an executable."

    if os.path.lexists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    run([executable], cwd=WORKSPACE, timeout=60)
    assert os.path.isfile(RESULTS_PATH), "Running the submitted executable did not create results.json."


def reference_values():
    reference_source = r'''
package main

import (
    "encoding/json"
    "fmt"
    "math"
    "math/rand"
    "sort"
)

func f(x float64) float64 { return math.Exp(-x) * math.Sin(5*x) }

func main() {
    exact := (5 - math.Exp(-2)*(math.Sin(10)+5*math.Cos(10))) / 26
    n := 4
    var integral float64
    for {
        h := 2.0 / float64(n)
        sum := 0.5*f(0) + 0.5*f(2)
        for i := 1; i < n; i++ {
            sum += f(float64(i) * h)
        }
        integral = h * sum
        if math.Abs(integral-exact) < 1e-4 {
            break
        }
        n *= 2
    }

    h := 2.0 / float64(n)
    derivative := (f(1+h) - f(1-h)) / (2*h)
    rand.Seed(42)
    estimates := make([]float64, 10000)
    for i := range estimates {
        forward := f(1+h) + 0.05*rand.NormFloat64()
        backward := f(1-h) + 0.05*rand.NormFloat64()
        estimates[i] = (forward - backward) / (2*h)
    }
    sort.Float64s(estimates)

    result := map[string]interface{}{
        "refined_N": n,
        "integral_error": math.Abs(integral-exact),
        "derivative_estimate": derivative,
        "lower_249": estimates[249],
        "lower_250": estimates[250],
        "upper_9749": estimates[9749],
        "upper_9750": estimates[9750],
    }
    b, _ := json.Marshal(result)
    fmt.Println(string(b))
}
'''
    path = "/tmp/reference_analyzer.go"
    with open(path, "w", encoding="utf-8") as f:
        f.write(reference_source)
    output = run(["go", "run", path], timeout=60).stdout
    return json.loads(output)


def test_results_file_exists():
    assert os.path.exists(RESULTS_PATH), f"File {RESULTS_PATH} does not exist."
    assert os.path.isfile(RESULTS_PATH), f"Path {RESULTS_PATH} is not a file."


def test_results_json_content():
    assert os.path.exists(RESULTS_PATH), f"File {RESULTS_PATH} does not exist."
    with open(RESULTS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")

    expected_keys = {"refined_N", "integral_error", "derivative_estimate", "ci_lower", "ci_upper"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in results.json: {missing_keys}"

    assert data["refined_N"] == 256, f"Expected refined_N to be 256, got {data['refined_N']}"
    assert 0.000030 <= data["integral_error"] <= 0.000035, f"Expected integral_error between 0.000030 and 0.000035, got {data['integral_error']}"
    assert 0.870 <= data["derivative_estimate"] <= 0.878, f"Expected derivative_estimate between 0.870 and 0.878, got {data['derivative_estimate']}"
    assert -8.5 <= data["ci_lower"] <= -7.5, f"Expected ci_lower between -8.5 and -7.5, got {data['ci_lower']}"
    assert 9.2 <= data["ci_upper"] <= 10.2, f"Expected ci_upper between 9.2 and 10.2, got {data['ci_upper']}"

    for key in expected_keys - {"refined_N"}:
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool)
        assert math.isfinite(data[key]), f"{key} must be finite."

    ref = reference_values()
    assert data["refined_N"] == ref["refined_N"]
    assert math.isclose(data["integral_error"], ref["integral_error"], rel_tol=0, abs_tol=1e-10), \
        f"Incorrect trapezoidal refinement error: {data['integral_error']}"
    assert math.isclose(data["derivative_estimate"], ref["derivative_estimate"], rel_tol=0, abs_tol=1e-10), \
        f"Incorrect central-difference derivative: {data['derivative_estimate']}"

    lower_min = min(ref["lower_249"], ref["lower_250"]) - 1e-8
    lower_max = max(ref["lower_249"], ref["lower_250"]) + 1e-8
    upper_min = min(ref["upper_9749"], ref["upper_9750"]) - 1e-8
    upper_max = max(ref["upper_9749"], ref["upper_9750"]) + 1e-8
    assert lower_min <= data["ci_lower"] <= lower_max, \
        f"Incorrect seeded bootstrap lower percentile: {data['ci_lower']}"
    assert upper_min <= data["ci_upper"] <= upper_max, \
        f"Incorrect seeded bootstrap upper percentile: {data['ci_upper']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
