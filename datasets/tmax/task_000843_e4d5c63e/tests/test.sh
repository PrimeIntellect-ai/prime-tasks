#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import pytest

SOURCE_PATH = "/home/user/analyze_graph.c"
OUTPUT_PATH = "/home/user/centralities.txt"
BINARY_PATH = "/tmp/analyze_graph_verified"

EXPECTED = {
    "A": 0.1481,
    "B": 0.3077,
    "C": 0.2667,
    "D": 0.2500,
    "E": 0.1739,
}
EXPECTED_LINES = [f"{node}: {EXPECTED[node]:.4f}" for node in sorted(EXPECTED)]


def test_program_and_centralities():
    assert os.path.exists(SOURCE_PATH), f"Source file {SOURCE_PATH} does not exist."
    source_stat = os.lstat(SOURCE_PATH)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE_PATH} is not a regular file."
    assert not stat.S_ISLNK(source_stat.st_mode), f"{SOURCE_PATH} must not be a symbolic link."

    if os.path.lexists(BINARY_PATH):
        os.remove(BINARY_PATH)

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE_PATH, "-o", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "Failed to compile analyze_graph.c:\n"
        + compile_result.stdout
        + compile_result.stderr
    )
    assert os.path.isfile(BINARY_PATH), "Compilation did not produce an executable."

    # The verified output must be freshly produced by the compiled submission.
    if os.path.lexists(OUTPUT_PATH):
        if os.path.isdir(OUTPUT_PATH) and not os.path.islink(OUTPUT_PATH):
            pytest.fail(f"Output path {OUTPUT_PATH} is a directory.")
        os.remove(OUTPUT_PATH)

    run_result = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, (
        "Compiled program exited unsuccessfully:\n"
        + run_result.stdout
        + run_result.stderr
    )

    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    output_stat = os.lstat(OUTPUT_PATH)
    assert stat.S_ISREG(output_stat.st_mode), f"Path {OUTPUT_PATH} is not a regular file."
    assert not stat.S_ISLNK(output_stat.st_mode), f"{OUTPUT_PATH} must not be a symbolic link."

    try:
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()

        assert len(lines) == len(EXPECTED), "Output must contain exactly one line per node."
        line_pattern = re.compile(r"^[A-Za-z][A-Za-z0-9_]*: [0-9]+\.[0-9]{4}$")
        assert all(line_pattern.fullmatch(line) for line in lines), (
            "Every line must have exactly the format 'NodeName: 0.XXXX'."
        )
        assert lines == EXPECTED_LINES, (
            "Centralities must be exact to four decimal places, contain no extra entries, "
            "and be sorted alphabetically."
        )

        agent_vals = {}
        for line in lines:
            parts = line.split(":")
            node = parts[0].strip()
            val = float(parts[1].strip())
            agent_vals[node] = val

        mse = 0.0
        for k, v in EXPECTED.items():
            if k in agent_vals:
                mse += (agent_vals[k] - v) ** 2
            else:
                mse += 1.0
        mse /= len(EXPECTED)
    except Exception as e:
        pytest.fail(f"Failed to parse {OUTPUT_PATH}: {e}")

    threshold = 0.001
    assert mse <= threshold, f"MSE {mse} exceeds the maximum allowed threshold of {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
