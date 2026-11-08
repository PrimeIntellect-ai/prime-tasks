#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest

PROFILER = "/home/user/profiler.go"
PIPELINE = "/home/user/run_pipeline.sh"
RESULTS = "/home/user/profile_results.json"


def read_results():
    assert os.path.isfile(RESULTS), f"{RESULTS} does not exist. Did you run the pipeline?"
    with open(RESULTS, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS} does not contain valid JSON.")

    assert "integral" in data, "JSON missing 'integral' key."
    assert "derivative" in data, "JSON missing 'derivative' key."
    assert isinstance(data["integral"], (int, float)), "'integral' must be a number."
    assert isinstance(data["derivative"], (int, float)), "'derivative' must be a number."
    return data


def run_checked(command, timeout=90):
    return subprocess.run(
        command,
        check=True,
        timeout=timeout,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_profiler_go_exists():
    """Verify that the Go program exists."""
    assert os.path.isfile(PROFILER), f"{PROFILER} does not exist."


def test_run_pipeline_sh_exists_and_executable():
    """Verify that the shell script exists and is executable."""
    assert os.path.isfile(PIPELINE), f"{PIPELINE} does not exist."
    st = os.stat(PIPELINE)
    assert bool(st.st_mode & stat.S_IXUSR), f"{PIPELINE} is not executable."


def test_pipeline_and_profiler_behavior():
    """Compile and exercise both the submitted pipeline and Go program."""
    with tempfile.TemporaryDirectory(prefix="profiler-verifier-") as td:
        backup = os.path.join(td, "profiler.go.backup")
        submitted_binary = os.path.join(td, "submitted-profiler")
        oracle_source = os.path.join(td, "oracle.go")
        oracle_binary = os.path.join(td, "oracle")
        shutil.copy2(PROFILER, backup)

        # Replace the source temporarily with an unpredictable canary. The pipeline
        # must compile this exact path and run it with the required seed 12345.
        canary_integral = secrets.randbelow(800000000) / 10000.0 + 10000.0
        canary_derivative = -(secrets.randbelow(800000000) / 10000.0 + 10000.0)
        canary_json = json.dumps({
            "integral": canary_integral,
            "derivative": canary_derivative,
        }, separators=(",", ":"))
        canary_source = f'''package main
import (
    "os"
)
func main() {{
    if len(os.Args) != 2 || os.Args[1] != "12345" {{
        os.Exit(37)
    }}
    if err := os.WriteFile("/home/user/profile_results.json", []byte({json.dumps(canary_json)}), 0644); err != nil {{
        panic(err)
    }}
}}
'''

        try:
            with open(PROFILER, "w") as f:
                f.write(canary_source)
            if os.path.exists(RESULTS):
                os.remove(RESULTS)
            run_checked(["/bin/bash", PIPELINE])
            canary_data = read_results()
            assert canary_data == json.loads(canary_json), (
                "run_pipeline.sh did not compile /home/user/profiler.go and run "
                "the resulting program with seed 12345"
            )
        finally:
            shutil.copy2(backup, PROFILER)

        # Build the submitted source independently so a fabricated pipeline output
        # cannot substitute for an implemented profiler.
        run_checked(["go", "build", "-o", submitted_binary, PROFILER])

        oracle_code = r'''package main
import (
    "fmt"
    "math"
    "math/rand"
    "os"
    "strconv"
)
func f(t float64) float64 {
    return 50 + 20*math.Sin(0.1*t) + 5*math.Cos(0.5*t)
}
func main() {
    seed, err := strconv.ParseInt(os.Args[1], 10, 64)
    if err != nil { panic(err) }
    rng := rand.New(rand.NewSource(seed))
    const n = 1000000
    sum := 0.0
    for i := 0; i < n; i++ {
        t := rng.Float64() * 100
        sum += f(t)
    }
    integral := 100 * (sum / n)
    const t = 50.0
    const h = 0.001
    derivative := (f(t+h) - f(t-h)) / (2*h)
    fmt.Printf("%.4f %.4f\n", integral, derivative)
}
'''
        with open(oracle_source, "w") as f:
            f.write(oracle_code)
        run_checked(["go", "build", "-o", oracle_binary, oracle_source])

        for seed in (1, 12345, 987654321):
            expected_output = run_checked([oracle_binary, str(seed)]).stdout.split()
            expected_integral, expected_derivative = map(float, expected_output)

            if os.path.exists(RESULTS):
                os.remove(RESULTS)
            run_checked([submitted_binary, str(seed)])
            actual = read_results()
            assert abs(actual["integral"] - expected_integral) < 1e-4, (
                f"For seed {seed}, expected integral {expected_integral}, "
                f"got {actual['integral']}"
            )
            assert abs(actual["derivative"] - expected_derivative) < 1e-4, (
                f"For seed {seed}, expected derivative {expected_derivative}, "
                f"got {actual['derivative']}"
            )

        # Execute the real submitted pipeline last so its required final output is
        # what remains at /home/user/profile_results.json.
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        run_checked(["/bin/bash", PIPELINE])


def test_profile_results_json():
    """Verify the contents of the generated JSON file."""
    data = read_results()

    # Values based on Go's math/rand with seed 12345 and N=1,000,000
    expected_integral = 5365.1053
    expected_derivative = 0.8982

    assert abs(data["integral"] - expected_integral) < 1e-4, \
        f"Expected integral to be approx {expected_integral}, got {data['integral']}"
    assert abs(data["derivative"] - expected_derivative) < 1e-4, \
        f"Expected derivative to be approx {expected_derivative}, got {data['derivative']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
