#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

SIM_DIR = "/home/user/sim"
SOURCE_PATH = os.path.join(SIM_DIR, "solver.c")
EXECUTABLE_PATH = os.path.join(SIM_DIR, "run_sim")
FINAL_PATH = os.path.join(SIM_DIR, "final_state.txt")
COMPILED_PATH = "/tmp/run_sim_from_solver"


def rk4_step(x, v, dt):
    def fx(v_): return v_
    def fv(x_, v_): return -0.2*v_ - x_

    k1x = fx(v)
    k1v = fv(x, v)

    k2x = fx(v + 0.5*dt*k1v)
    k2v = fv(x + 0.5*dt*k1x, v + 0.5*dt*k1v)

    k3x = fx(v + 0.5*dt*k2v)
    k3v = fv(x + 0.5*dt*k2x, v + 0.5*dt*k2v)

    k4x = fx(v + dt*k3v)
    k4v = fv(x + dt*k3x, v + dt*k3v)

    x_new = x + (dt/6.0)*(k1x + 2*k2x + 2*k3x + k4x)
    v_new = v + (dt/6.0)*(k1v + 2*k2v + 2*k3v + k4v)
    return x_new, v_new


def get_expected_values():
    x, v = 1.0, 0.0
    dt = 0.1
    for _ in range(100):
        x, v = rk4_step(x, v, dt)
    return x, v


def assert_final_state_contents():
    assert os.path.isfile(FINAL_PATH), f"{FINAL_PATH} does not exist."

    with open(FINAL_PATH, "r") as f:
        raw_content = f.read()
    content = raw_content.strip()

    assert content, f"{FINAL_PATH} is empty."

    pattern = r"t=10\.00000, x=([+-]?\d+\.\d{5}), v=([+-]?\d+\.\d{5})"
    exact_match = re.fullmatch(pattern + r"\n?", raw_content)
    assert exact_match is not None, (
        f"Content of {FINAL_PATH} must be exactly one line with exactly five decimal "
        f"places. Got: {raw_content!r}"
    )

    # Preserve the original parsing assertion.
    match = re.match(r"^t=10\.00000,\s*x=([+-]?\d+\.\d+),\s*v=([+-]?\d+\.\d+)$", content)
    assert match is not None, f"Content of {FINAL_PATH} does not match the required format. Got: {content}"

    actual_x = float(match.group(1))
    actual_v = float(match.group(2))
    expected_x, expected_v = get_expected_values()

    tolerance = 0.00002
    assert abs(actual_x - expected_x) <= tolerance, f"x value {actual_x} is not within {tolerance} of expected {expected_x:.5f}."
    assert abs(actual_v - expected_v) <= tolerance, f"v value {actual_v} is not within {tolerance} of expected {expected_v:.5f}."


def run_and_check(executable):
    if os.path.exists(FINAL_PATH):
        os.unlink(FINAL_PATH)
    subprocess.run([executable], cwd=SIM_DIR, check=True, timeout=10)
    assert_final_state_contents()


def test_sim_directory_exists():
    assert os.path.isdir(SIM_DIR), f"{SIM_DIR} directory does not exist."


def test_solver_c_exists():
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} does not exist."


def test_run_sim_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"{EXECUTABLE_PATH} does not exist."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not a gcc-compiled executable."


def test_submitted_executable_generates_correct_output():
    run_and_check(EXECUTABLE_PATH)


def test_solver_source_compiles_and_generates_correct_output():
    subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE_PATH, "-o", COMPILED_PATH, "-lm"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    run_and_check(COMPILED_PATH)


def test_final_state_file_contents():
    assert_final_state_contents()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
