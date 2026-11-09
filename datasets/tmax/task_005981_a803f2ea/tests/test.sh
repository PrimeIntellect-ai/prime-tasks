#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shutil
import subprocess
import tempfile

HOME = "/home/user"
SIMULATE = os.path.join(HOME, "simulate.go")
MODEL = os.path.join(HOME, "model.go")
REFERENCE = os.path.join(HOME, "reference_data.txt")
REPORT = os.path.join(HOME, "regression_report.txt")

EXPECTED_MODEL = '''package main

import "math/rand"

// LatencySample simulates a bimodal latency distribution:
// 90% of requests are fast, 10% hit a slow path.
func LatencySample(rng *rand.Rand) float64 {
\tif rng.Float64() < 0.90 {
\t\treturn rng.NormFloat64()*12.5 + 105.0
\t}
\treturn rng.NormFloat64()*45.0 + 520.0
}
'''


def nearest_rank(values):
    values = sorted(values)
    return values[math.ceil(0.95 * len(values)) - 1]


def expected_report(hist_p95, sim_p95):
    status = "REGRESSION DETECTED" if sim_p95 > 1.20 * hist_p95 else "PERFORMANCE OK"
    return (
        f"Historical P95: {hist_p95:.2f}\n"
        f"Simulated P95: {sim_p95:.2f}\n"
        f"Status: {status}"
    )


def run_go(cwd):
    env = os.environ.copy()
    env["GO111MODULE"] = "off"
    result = subprocess.run(
        ["go", "run", "model.go", "simulate.go"],
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, (
        "The submitted Go program did not run successfully.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_submission():
    assert os.path.isfile(SIMULATE), (
        f"Missing file: {SIMULATE}. The task requires saving the Go program as simulate.go."
    )
    assert os.path.isfile(MODEL), f"Missing file: {MODEL}"
    with open(MODEL, "r") as f:
        assert f.read() == EXPECTED_MODEL, "model.go was modified."

    # Exercise the submitted program with a private instrumented model and private
    # reference data. The model verifies the exact RNG seed/stream and records only
    # the 100,000th LatencySample call; an additional call causes execution to fail.
    work = tempfile.mkdtemp(prefix="simulate_verify_")
    marker = os.path.join(work, "called_100000")
    multiplier = secrets.randbelow(99999) + 2
    base = secrets.randbelow(200) + 20
    hist_values = [float(secrets.randbelow(5000)) / 10.0 for _ in range(257)]
    sim_values = [base + ((i * multiplier) % 100003) / 10.0 for i in range(1, 100001)]
    challenge_expected = expected_report(nearest_rank(hist_values), nearest_rank(sim_values))

    model_source = f'''package main

import (
    "fmt"
    "math/rand"
    "os"
)

var verifierExpected = rand.New(rand.NewSource(42))
var verifierCalls int

func LatencySample(rng *rand.Rand) float64 {{
    got := rng.Int63()
    want := verifierExpected.Int63()
    if got != want {{
        panic(fmt.Sprintf("LatencySample received an RNG not initialized with seed 42, or the RNG stream was altered: got %d want %d", got, want))
    }}
    verifierCalls++
    if verifierCalls > 100000 {{
        panic("LatencySample called more than 100,000 times")
    }}
    if verifierCalls == 100000 {{
        if err := os.WriteFile({marker!r}, []byte("ok"), 0600); err != nil {{
            panic(err)
        }}
    }}
    return float64({base}) + float64((verifierCalls*{multiplier})%100003)/10.0
}}
'''
    # Python repr uses compatible quoted strings for this slash-only marker path.
    with open(os.path.join(work, "model.go"), "w") as f:
        f.write(model_source)
    shutil.copyfile(SIMULATE, os.path.join(work, "simulate.go"))

    with open(REFERENCE, "rb") as f:
        original_reference = f.read()
    original_report = None
    if os.path.isfile(REPORT):
        with open(REPORT, "rb") as f:
            original_report = f.read()

    try:
        with open(REFERENCE, "w") as f:
            for value in hist_values:
                f.write(f"{value}\n")
        if os.path.exists(REPORT):
            os.remove(REPORT)

        run_go(work)
        assert os.path.isfile(marker), "LatencySample was called fewer than 100,000 times."
        assert os.path.isfile(REPORT), f"Missing file: {REPORT}. The report was not generated."
        with open(REPORT, "r") as f:
            actual = f.read().strip()
        assert actual == challenge_expected, (
            "The program produced an incorrect report for verifier-generated inputs.\n"
            f"Expected:\n{challenge_expected}\n\nActual:\n{actual}"
        )
    finally:
        with open(REFERENCE, "wb") as f:
            f.write(original_reference)
        if original_report is None:
            if os.path.exists(REPORT):
                os.remove(REPORT)
        else:
            with open(REPORT, "wb") as f:
                f.write(original_report)
        shutil.rmtree(work, ignore_errors=True)

    # Run against the supplied artifacts and retain the original report assertions.
    run_go(HOME)
    assert os.path.isfile(REPORT), f"Missing file: {REPORT}. The report was not generated."

    with open(REFERENCE, "r") as f:
        data = [float(line.strip()) for line in f if line.strip()]
    hist_p95 = nearest_rank(data)
    expected_hist_str = f"{hist_p95:.2f}"
    expected_sim_str = "520.25"
    expected_status = (
        "REGRESSION DETECTED"
        if float(expected_sim_str) > 1.20 * hist_p95
        else "PERFORMANCE OK"
    )
    expected_content = (
        f"Historical P95: {expected_hist_str}\n"
        f"Simulated P95: {expected_sim_str}\n"
        f"Status: {expected_status}"
    )
    with open(REPORT, "r") as f:
        actual_content = f.read().strip()
    assert actual_content == expected_content, (
        f"The content of {REPORT} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )


if __name__ == "__main__":
    test_submission()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
