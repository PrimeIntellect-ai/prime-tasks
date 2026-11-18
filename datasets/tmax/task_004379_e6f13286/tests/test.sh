#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify.py
import math
import os
import random
import re
import stat
import subprocess

WORKSPACE = "/home/user/consensus_debugger"
RESULT = "/home/user/result.txt"
SIM_C = os.path.join(WORKSPACE, "sim.c")
MAKEFILE = os.path.join(WORKSPACE, "Makefile")
SIM = os.path.join(WORKSPACE, "sim")
TRAFFIC = os.path.join(WORKSPACE, "traffic.log")
CANONICAL_TRAFFIC = b"10.5\n11.0\n10.8\n11.2\n10.9\n11.1\n11.0\n11.05\n11.02\n11.0\n"


def ema(readings):
    estimate = 10.0
    for reading in readings:
        estimate += 0.2 * (reading - estimate)
        # Inputs and estimates used here are positive, so this matches C round().
        estimate = math.floor(estimate * 10000.0 + 0.5) / 10000.0
    return estimate


def run_sim(readings=None, with_debug=True):
    if readings is not None:
        with open(TRAFFIC, "w", encoding="ascii") as f:
            for value in readings:
                f.write(f"{value:.4f}\n")

    env = os.environ.copy()
    env.pop("AGGREGATOR_MODE", None)
    if with_debug:
        env["AGGREGATOR_MODE"] = "DEBUG"

    return subprocess.run(
        [SIM], cwd=WORKSPACE, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )


def parse_output(proc):
    assert proc.returncode == 0, f"sim failed: stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    match = re.fullmatch(r"Final estimate: ([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*", proc.stdout)
    assert match, f"Unexpected simulator output: {proc.stdout!r}"
    return float(match.group(1)), match.group(1)


# Preserve the original verifier's assertions.
assert os.path.isfile(RESULT), "result.txt does not exist at /home/user/result.txt"
with open(RESULT, "r", encoding="utf-8") as f:
    result_text = f.read().strip()
try:
    result_value = float(result_text)
except ValueError:
    raise AssertionError(f"result.txt does not contain a valid floating-point number: {result_text!r}")
assert 10.8 <= result_value <= 11.2, f"Value {result_value} is outside 10.8 - 11.2"

assert os.path.isfile(MAKEFILE), "Makefile is missing"
with open(MAKEFILE, "r", encoding="utf-8") as f:
    makefile_content = f.read()
assert "-lm" in makefile_content, "Makefile does not contain the required -lm linker flag"

assert os.path.isfile(SIM_C), "sim.c is missing"
with open(SIM_C, "r", encoding="utf-8") as f:
    sim_c_content = f.read()
assert "double alpha = 1.2;" not in sim_c_content, "sim.c still contains the buggy alpha declaration"

assert os.path.isfile(TRAFFIC), "traffic.log is missing"
with open(TRAFFIC, "rb") as f:
    original_traffic = f.read()
assert original_traffic == CANONICAL_TRAFFIC, "traffic.log was modified"

# Rebuild from the submitted source and Makefile rather than trusting a planted file.
if os.path.lexists(SIM):
    os.remove(SIM)
build = subprocess.run(
    ["make", "-B", "sim"], cwd=WORKSPACE, text=True,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
)
assert build.returncode == 0, f"make failed: stdout={build.stdout!r}, stderr={build.stderr!r}"
assert os.path.isfile(SIM), "The compiled sim executable does not exist"
assert os.access(SIM, os.X_OK), "The sim file is not executable"
with open(SIM, "rb") as f:
    assert f.read(4) == b"\x7fELF", "sim is not a compiled ELF executable"

try:
    # The executable must enforce the required environment configuration.
    missing_env = run_sim(with_debug=False)
    assert missing_env.returncode != 0, "sim succeeds without AGGREGATOR_MODE=DEBUG"

    # Check the canonical replay and independently derive its exact answer.
    canonical_readings = [float(x) for x in CANONICAL_TRAFFIC.decode("ascii").splitlines()]
    canonical_expected = ema(canonical_readings)
    canonical_proc = run_sim(with_debug=True)
    canonical_actual, canonical_text = parse_output(canonical_proc)
    assert canonical_text == f"{canonical_expected:.4f}", (
        f"sim produced {canonical_text}, expected {canonical_expected:.4f}"
    )
    assert result_text == f"{canonical_expected:.4f}", (
        f"result.txt contains {result_text!r}, expected {canonical_expected:.4f}"
    )

    # Exercise the built simulator on unpredictable inputs to reject hard-coded output.
    rng = random.SystemRandom()
    for _ in range(4):
        readings = [rng.randrange(50000, 150001) / 10000.0 for _ in range(rng.randrange(3, 16))]
        expected = ema(readings)
        proc = run_sim(readings=readings, with_debug=True)
        actual, actual_text = parse_output(proc)
        assert actual_text == f"{expected:.4f}", (
            f"Incorrect EMA result for {readings}: got {actual_text}, expected {expected:.4f}"
        )
finally:
    with open(TRAFFIC, "wb") as f:
        f.write(original_traffic)
PY_EOF

if python3 /tmp/verify.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
