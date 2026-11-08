#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess

PROJECT = "/home/user/model_fitter"
SOURCE = os.path.join(PROJECT, "src/main.rs")
DATASET = "/home/user/dataset.csv"
PARAMS = "/home/user/optimized_params.txt"
BINARY = os.path.join(PROJECT, "target/release/model_fitter")


def run_binary():
    result = subprocess.run(
        [BINARY],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def extract_params(output):
    matches = re.findall(r"Final params:\s*a=(-?\d+\.\d{2}),\s*b=(-?\d+\.\d{2})", output)
    assert matches, f"Program did not print final parameters in the required form: {output!r}"
    return matches[-1]


def test_optimized_params_file():
    assert os.path.isfile(PARAMS), f"Log file {PARAMS} was not found."
    with open(PARAMS, "r") as f:
        content = f.read().strip()
    assert content.replace(" ", "") == "a=2.00,b=3.00", f"Unexpected log contents: {content!r}"


def test_rust_code_modified():
    assert os.path.isfile(SOURCE), f"Rust source file {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()

    code = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    code = re.sub(r"//.*", "", code)
    shared_add = re.compile(
        r"\*\s*[A-Za-z_]\w*\s*\.lock\s*\(\s*\)\s*\.unwrap\s*\(\s*\)\s*\+=",
        re.S,
    )
    assert not shared_add.search(code), (
        "The source still accumulates floating-point values directly through a shared Mutex; "
        "the reduction must occur in a fixed order."
    )


def test_compiled_program_is_deterministic_and_fits_data():
    subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert os.path.isfile(BINARY), "Cargo did not produce the release executable."

    original_one = run_binary()
    original_two = run_binary()
    assert original_one == original_two, "Repeated executions produced different output."
    assert extract_params(original_one) == ("2.00", "3.00"), original_one

    backup = DATASET + ".verifier-backup"
    shutil.copyfile(DATASET, backup)
    try:
        # Generate an independent noiseless dataset from the numerical integral
        # implemented by the supplied model, using parameters unknown to the submission.
        hidden_a, hidden_b = -1.0, 1.0
        with open(DATASET, "w") as f:
            for i in range(100):
                x = i * 0.1
                steps = 100
                dt = x / steps
                basis_a = 0.0
                basis_b = 0.0
                for j in range(steps):
                    t = j * dt
                    import math
                    basis_a += math.cos(t) * dt
                    basis_b += math.sin(t) * dt
                y = hidden_a * basis_a + hidden_b * basis_b
                f.write(f"{x:.17g},{y:.17g}\n")

        hidden_one = run_binary()
        hidden_two = run_binary()
        assert hidden_one == hidden_two, "Hidden-data executions were not reproducible."
        assert extract_params(hidden_one) == ("-1.00", "1.00"), (
            "The executable did not optimize the independently generated dataset: " + hidden_one
        )
    finally:
        shutil.move(backup, DATASET)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
