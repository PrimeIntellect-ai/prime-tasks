#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

PROJECT = "/home/user/sim_project"
CPP_PATH = os.path.join(PROJECT, "simulator.cpp")
BINARY_PATH = os.path.join(PROJECT, "simulator")
RESULT_PATH = "/home/user/result.txt"
LARGE_INPUT = os.path.join(PROJECT, "large_input.txt")


def test_result_file():
    assert os.path.isfile(RESULT_PATH), f"File {RESULT_PATH} is missing."

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    assert "FINAL: 2000.0002" in content, \
        f"Expected 'FINAL: 2000.0002' in {RESULT_PATH}, but found: {content}"


def test_simulator_cpp_fixed():
    assert os.path.isfile(CPP_PATH), f"File {CPP_PATH} is missing."

    with open(CPP_PATH, "r") as f:
        content = f.read()

    assert "float current_pos" not in content, "current_pos is still declared as float."
    assert "float v, dt" not in content and "float v" not in content and "float dt" not in content, \
        "v or dt are still declared as float."

    assert re.search(r"double\s+current_pos", content), \
        "current_pos must be declared as double."
    assert re.search(r"double\s+v\s*,\s*dt|double\s+v\s*;\s*double\s+dt|double\s+dt\s*,\s*v", content), \
        "v and dt must be declared as double."


def test_simulator_compiled_from_source():
    # Preserve the original assertion that the agent left an executable artifact.
    assert os.path.isfile(BINARY_PATH), f"Compiled binary {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled binary {BINARY_PATH} is not executable."

    # Force the provided Makefile to rebuild the submitted source.
    os.remove(BINARY_PATH)
    build = subprocess.run(
        ["make", "-B", "simulator"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert build.returncode == 0, f"Makefile build failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(BINARY_PATH), f"Compiled binary {BINARY_PATH} is missing after make."
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled binary {BINARY_PATH} is not executable after make."

    # Ensure make produced the program represented by simulator.cpp, rather than a dummy artifact.
    independently_built = "/tmp/simulator_independent_build"
    direct = subprocess.run(
        ["g++", "-O3", "-std=c++17", "simulator.cpp", "-o", independently_built],
        cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert direct.returncode == 0, f"Submitted source does not compile:\n{direct.stdout}\n{direct.stderr}"
    with open(BINARY_PATH, "rb") as made, open(independently_built, "rb") as direct_binary:
        assert made.read() == direct_binary.read(), \
            "The Makefile-built simulator is not the binary produced from simulator.cpp."


def test_simulator_runs_large_input_and_result_matches():
    run = subprocess.run(
        [BINARY_PATH, LARGE_INPUT], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert run.returncode == 0, \
        f"Simulator failed validation on large_input.txt:\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"

    output_lines = [line.strip() for line in run.stdout.splitlines() if line.strip()]
    assert output_lines, "Simulator produced no output."
    final_line = output_lines[-1]
    assert final_line == "FINAL: 2000.0002", f"Unexpected final simulator output: {final_line}"

    with open(RESULT_PATH, "r") as f:
        saved = f.read().strip()
    assert saved == final_line, \
        f"{RESULT_PATH} must contain exactly the simulator's final output line; found: {saved!r}"


def test_simulator_precision_on_unseen_input():
    # A large exactly representable starting position makes 0.001 increments disappear
    # under float accumulation, while double accumulation remains within CHECK tolerance.
    baseline = secrets.randbelow(40000) * 1024 + 50_000_000
    added_whole_units = 12 + secrets.randbelow(8)
    steps = added_whole_units * 1000
    expected = baseline + added_whole_units
    input_path = f"/tmp/precision_case_{secrets.token_hex(12)}.txt"

    with open(input_path, "w") as f:
        f.write(f"MOVE {baseline} 1 1\n")
        f.write(f"MOVE 1 0.001 {steps}\n")
        f.write(f"CHECK {expected}\n")

    run = subprocess.run(
        [BINARY_PATH, input_path], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert run.returncode == 0, \
        f"Simulator failed the generated precision validation:\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"
    assert "SUCCESS" in run.stdout, "Simulator did not report success for the generated valid case."

    output_lines = [line.strip() for line in run.stdout.splitlines() if line.strip()]
    assert output_lines and output_lines[-1].startswith("FINAL: "), \
        f"Missing FINAL line in output: {run.stdout!r}"
    try:
        actual = float(output_lines[-1].split(":", 1)[1].strip())
    except ValueError as exc:
        raise AssertionError(f"Invalid FINAL value: {output_lines[-1]!r}") from exc
    assert abs(actual - expected) <= 0.02, \
        f"Generated case expected approximately {expected}, but simulator printed {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
