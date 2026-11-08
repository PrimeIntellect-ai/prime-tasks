#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

CPP_FILE = "/home/user/generate.cpp"
RESULT_FILE = "/home/user/result.txt"
BINARY_FILE = "/tmp/generate_submission"


def test_generate_cpp_exists_and_uses_openmp():
    """Check, compile, and execute the submitted OpenMP C++ program."""
    assert os.path.isfile(CPP_FILE), f"File {CPP_FILE} does not exist."

    with open(CPP_FILE, "r") as f:
        content = f.read()

    # Preserve the original OpenMP assertion and additionally require an
    # OpenMP parallel-for directive rather than an arbitrary mention.
    assert "omp" in content.lower(), f"File {CPP_FILE} does not seem to use OpenMP (no 'omp' found)."
    without_comments = re.sub(r"//.*?$|/\*.*?\*/", "", content, flags=re.MULTILINE | re.DOTALL)
    assert re.search(r"^\s*#\s*pragma\s+omp\s+parallel\s+for\b", without_comments, re.MULTILINE), \
        "generate.cpp must parallelize the simulation loop with an OpenMP parallel-for directive."

    if os.path.exists(BINARY_FILE):
        os.remove(BINARY_FILE)
    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)

    compiled = subprocess.run(
        ["g++", "-O3", "-fopenmp", CPP_FILE, "-o", BINARY_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compiled.returncode == 0, f"generate.cpp failed to compile with OpenMP:\n{compiled.stderr}"
    assert os.path.isfile(BINARY_FILE) and os.access(BINARY_FILE, os.X_OK), \
        "Compilation did not produce an executable."

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    executed = subprocess.run(
        [BINARY_FILE],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert executed.returncode == 0, f"Compiled program failed when executed:\n{executed.stderr}"


def test_result_txt_exists_and_correct():
    """Check that the executed program produced the exact expected sum."""
    assert os.path.isfile(RESULT_FILE), f"File {RESULT_FILE} does not exist. Did you run the compiled program?"

    s = 0.0
    for i in range(1000):
        k = 0.1 + i * (0.9 / 999)
        y = 1.0
        for _ in range(1000):
            y = y * (1.0 - k * 0.01)
        s += y
    expected_val = f"{s:.4f}"

    with open(RESULT_FILE, "r") as f:
        content = f.read().strip()

    assert content == expected_val, f"Expected {expected_val} in {RESULT_FILE}, but found '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
