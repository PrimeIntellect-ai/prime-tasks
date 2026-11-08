#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

SOURCE = "/home/user/sim.c"
RESULT = "/home/user/result.txt"
BINARY = "/tmp/sim_submission"


def test_sim_c_exists():
    """Verify that the C source file was created."""
    assert os.path.isfile(SOURCE), "/home/user/sim.c does not exist."


def test_result_txt_exists():
    """Verify that the requested result file was created by the agent."""
    assert os.path.isfile(RESULT), "/home/user/result.txt does not exist."


def reference_values():
    primer = "ATGCGATCG"
    target = "ATGCGATCT"
    score = sum(1 if a == b else -1 for a, b in zip(primer, target))

    n = 101
    dx = 0.01
    dt = 0.001
    diffusion = score * 0.001
    ratio = diffusion * dt / (dx * dx)

    u = [math.exp(-100.0 * (i * dx - 0.5) ** 2) for i in range(n)]
    u[0] = 0.0
    u[-1] = 0.0

    for _ in range(100):
        next_u = [0.0] * n
        for i in range(1, n - 1):
            next_u[i] = u[i] + ratio * (u[i + 1] - 2.0 * u[i] + u[i - 1])
        u = next_u

    mass = sum(u)
    q = 1.0 / n
    kl = 0.0
    for value in u:
        if value > 0.0:
            p = value / mass
            kl += p * math.log(p / q)
    return score, mass, kl


def test_result_values():
    """Compile and execute sim.c, then verify its generated output independently."""
    subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-lm", "-o", BINARY],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )

    if os.path.exists(RESULT):
        os.remove(RESULT)

    subprocess.run(
        [BINARY],
        cwd="/home/user",
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert os.path.isfile(RESULT), "The compiled program did not create /home/user/result.txt."

    with open(RESULT, "r") as f:
        content = f.read()

    match = re.fullmatch(
        r"Score: (-?\d+)\nTotal Mass: (-?\d+\.\d{6})\nKL: (-?\d+\.\d{6})\n?",
        content,
    )
    assert match is not None, "result.txt does not have the required three-line format with six decimal places."

    score = int(match.group(1))
    mass = float(match.group(2))
    kl = float(match.group(3))
    expected_score, expected_mass, expected_kl = reference_values()

    assert score == expected_score, f"Expected Score to be {expected_score}, but got {score}"
    assert math.isclose(mass, expected_mass, rel_tol=0.0, abs_tol=5.1e-7), \
        f"Expected Total Mass {expected_mass:.6f}, but got {mass:.6f}"
    assert math.isclose(kl, expected_kl, rel_tol=0.0, abs_tol=5.1e-7), \
        f"Expected KL {expected_kl:.6f}, but got {kl:.6f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
