#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import numpy as np

GO_FILE = "/home/user/sim/main.go"
SIM_DIR = "/home/user/sim"
BINARY = "/tmp/simulation-under-test"
FLOAT_LINE = re.compile(r"^[+-]?(?:\d+\.\d{15,})(?:[eE][+-]?\d+)?$")


def expected_after_1000_iterations():
    # Independently perform the specified diffusion using the weights from the image.
    edges = [
        (0, 1, 0.3333333333333333),
        (0, 2, 0.6666666666666666),
        (1, 0, 0.1),
        (1, 3, 0.9),
        (2, 3, 1.0),
        (3, 0, 1.0),
    ]
    state = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)
    for _ in range(1000):
        next_state = np.zeros(4, dtype=np.float64)
        for src, dst, weight in edges:
            next_state[dst] += state[src] * weight
        state = next_state
    return state


def parse_output(text, description):
    lines = text.splitlines()
    assert len(lines) == 4, f"Expected exactly 4 lines in {description}, found {len(lines)}"
    for line in lines:
        assert FLOAT_LINE.fullmatch(line.strip()), (
            f"Each value in {description} must be formatted with at least 15 decimal places: {line!r}"
        )
    try:
        values = np.array([float(line.strip()) for line in lines], dtype=np.float64)
    except ValueError as e:
        assert False, f"Could not parse floats from {description}: {e}"
    assert np.all(np.isfinite(values)), f"Non-finite value found in {description}: {values}"
    return values


def build_program():
    assert os.path.isfile(GO_FILE), f"Go file {GO_FILE} does not exist."
    res = subprocess.run(
        ["go", "build", "-o", BINARY, "main.go"],
        cwd=SIM_DIR,
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"Go program failed to build: {res.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "go build did not produce an executable"


def test_reproducibility():
    """Verify that running the Go simulation 5 times produces identical output."""
    assert os.path.isfile(GO_FILE), f"Go file {GO_FILE} does not exist."

    outputs = []
    for _ in range(5):
        res = subprocess.run(["go", "run", GO_FILE], capture_output=True, text=True)
        assert res.returncode == 0, f"Go program failed to run: {res.stderr}"
        outputs.append(res.stdout.strip())

    assert len(set(outputs)) == 1, "Variance > 0: Output is not reproducible across runs."


def test_built_program_computes_requested_simulation():
    """Build and execute the artifact, then compare its output to an independent 1000-step simulation."""
    build_program()
    outputs = []
    for _ in range(5):
        res = subprocess.run([BINARY], capture_output=True, text=True)
        assert res.returncode == 0, f"Built Go program failed to run: {res.stderr}"
        assert res.stderr == "", f"Built Go program wrote unexpected stderr: {res.stderr}"
        outputs.append(res.stdout.strip())

    assert len(set(outputs)) == 1, "Built program output is not perfectly reproducible."
    actual = parse_output(outputs[0], "the Go program's stdout")
    expected = expected_after_1000_iterations()
    mse = np.mean((actual - expected) ** 2)
    assert mse < 1e-20, (
        f"Program stdout does not match the independently computed 1000-iteration result; "
        f"MSE={mse}, output={actual}, expected={expected}"
    )


def test_steady_state_mse():
    """Verify that the steady state output matches the analytical solution with MSE < 1e-20."""
    target = np.array([0.3448275862068966, 0.1149425287356322, 0.2298850574712644, 0.3103448275862069])

    file_path = "/home/user/steady_state.txt"
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist."

    with open(file_path, "r") as f:
        lines = f.readlines()

    assert len(lines) == 4, f"Expected exactly 4 lines in {file_path}, found {len(lines)}"

    try:
        agent_state = np.array([float(x.strip()) for x in lines])
    except ValueError as e:
        assert False, f"Could not parse floats from {file_path}: {e}"

    assert np.all(np.isfinite(agent_state)), f"Non-finite value found in {file_path}: {agent_state}"
    for line in lines:
        assert FLOAT_LINE.fullmatch(line.strip()), (
            f"Each value in {file_path} must be formatted with at least 15 decimal places: {line!r}"
        )

    mse = np.mean((agent_state - target)**2)
    assert mse < 1e-20, f"MSE {mse} is not less than threshold 1e-20. Agent state: {agent_state}"

    # Tie the saved result to actual execution rather than accepting an unrelated hardcoded file.
    build_program()
    res = subprocess.run([BINARY], capture_output=True, text=True)
    assert res.returncode == 0, f"Built Go program failed to run: {res.stderr}"
    runtime_state = parse_output(res.stdout.strip(), "the Go program's stdout")
    runtime_mse = np.mean((agent_state - runtime_state) ** 2)
    assert runtime_mse < 1e-28, (
        f"{file_path} is not the result emitted by the Go simulation; "
        f"MSE={runtime_mse}, file={agent_state}, runtime={runtime_state}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
