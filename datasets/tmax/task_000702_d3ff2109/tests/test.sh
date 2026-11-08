#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess

TRACE = "/home/user/trace.csv"
ANALYZE = "/home/user/analyze.rs"
ESTIMATE = "/home/user/k_estimate.txt"
SIM_SOURCE = "/home/user/sim_engine/sim.rs"
SIM_BIN = "/tmp/sim_verify"
ANALYZE_BIN = "/tmp/analyze_verify"


def run(cmd, timeout=90):
    return subprocess.run(cmd, check=True, timeout=timeout, cwd="/home/user",
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def read_estimate():
    assert os.path.isfile(ESTIMATE), f"File {ESTIMATE} is missing. Did you save the estimate?"
    with open(ESTIMATE, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"[0-9]+\.[0-9]", content), \
        f"Estimate must be rounded to exactly one decimal place, got '{content}'."
    return content, float(content)


def write_euler_trace(path, k, frequency):
    import math
    dt = 0.01
    omega2 = (2.0 * math.pi * frequency) ** 2
    y = 1.0
    v = 0.0
    with open(path, "w") as f:
        for i in range(201):
            f.write(f"{i * dt:.2f},{y:.17g}\n")
            old_y = y
            old_v = v
            y = old_y + dt * old_v
            v = old_v + dt * (-k * old_v - omega2 * old_y)


def test_complete_analysis_program():
    # Compile and run the supplied simulator from its source, rather than trusting
    # a trace left by the submission.
    assert os.path.isfile(SIM_SOURCE), f"Simulator source {SIM_SOURCE} is missing."
    run(["rustc", SIM_SOURCE, "-O", "-o", SIM_BIN])
    if os.path.exists(TRACE):
        os.remove(TRACE)
    run([SIM_BIN])

    # Preserve the original verifier's trace assertions.
    assert os.path.isfile(TRACE), f"File {TRACE} is missing. Did you compile and run sim.rs?"
    assert os.path.getsize(TRACE) > 0, f"File {TRACE} is empty."

    # Preserve the original verifier's analysis-source assertions and actually
    # compile the artifact using rustc alone.
    assert os.path.isfile(ANALYZE), f"File {ANALYZE} is missing. Did you write the analysis program?"
    assert os.path.getsize(ANALYZE) > 0, f"File {ANALYZE} is empty."
    run(["rustc", ANALYZE, "-O", "-o", ANALYZE_BIN])

    # Run against the simulator's real trace and preserve the original exact
    # result assertion.
    if os.path.exists(ESTIMATE):
        os.remove(ESTIMATE)
    run([ANALYZE_BIN])
    content, _ = read_estimate()
    assert content == "0.8", f"Expected k estimate to be '0.8', but got '{content}'."

    original_trace = open(TRACE, "rb").read()
    try:
        # Exercise the compiled analyzer on an unpredictable trace generated
        # directly from the required Euler equations. A fixed 0.8 answer cannot
        # pass this check.
        rng = secrets.SystemRandom()
        challenge_k = rng.uniform(1.25, 1.70)
        write_euler_trace(TRACE, challenge_k, 1)
        if os.path.exists(ESTIMATE):
            os.remove(ESTIMATE)
        run([ANALYZE_BIN])
        _, estimate = read_estimate()
        assert abs(estimate - challenge_k) <= 0.21, \
            f"Analyzer returned {estimate:.1f} for a generated trace with damping {challenge_k:.3f}."
    finally:
        with open(TRACE, "wb") as f:
            f.write(original_trace)

    # Leave and verify the requested result for the actual simulator trace.
    if os.path.exists(ESTIMATE):
        os.remove(ESTIMATE)
    run([ANALYZE_BIN])
    content, _ = read_estimate()
    assert content == "0.8", f"Expected k estimate to be '0.8', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
