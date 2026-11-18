#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile


def compute_expected():
    x = [1.0, 2.0, 3.0, 4.0, 5.0]
    y = [3.2, 5.1, 6.8, 9.1, 10.9]
    w, b = 0.0, 0.0
    lr = 0.02

    for _ in range(100):
        grad_w = 0.0
        grad_b = 0.0
        for xi, yi in zip(x, y):
            pred = w * xi + b
            grad_w += -2.0 / 5.0 * xi * (yi - pred)
            grad_b += -2.0 / 5.0 * (yi - pred)
        w -= lr * grad_w
        b -= lr * grad_b

    log_post = 0.0
    for xi, yi in zip(x, y):
        pred = w * xi + b
        log_post += -0.5 * (yi - pred) ** 2

    return w, b, log_post


def parse_output(text):
    content = text.strip().split('\n')
    assert len(content) >= 2, "Output must have at least two lines."

    line1 = content[0]
    line2 = content[1]

    match1 = re.search(r'GD w:\s*(-?\d+\.\d+),\s*b:\s*(-?\d+\.\d+)', line1)
    assert match1 is not None, f"Line 1 format is incorrect: {line1}"

    match2 = re.search(r'LogPosterior:\s*(-?\d+\.\d+)', line2)
    assert match2 is not None, f"Line 2 format is incorrect: {line2}"

    return float(match1.group(1)), float(match1.group(2)), float(match2.group(1))


def assert_expected_values(text):
    actual_w, actual_b, actual_log_post = parse_output(text)
    w, b, log_post = compute_expected()
    tol = 0.0005
    assert abs(actual_w - w) <= tol, f"Expected w ~ {w:.4f}, but got {actual_w}"
    assert abs(actual_b - b) <= tol, f"Expected b ~ {b:.4f}, but got {actual_b}"
    assert abs(actual_log_post - log_post) <= tol, \
        f"Expected LogPosterior ~ {log_post:.4f}, but got {actual_log_post}"


def test_dataset_exists():
    """Check that dataset.csv exists and has the exact required content."""
    dataset_path = "/home/user/dataset.csv"
    assert os.path.isfile(dataset_path), f"File {dataset_path} does not exist."

    with open(dataset_path, "r") as f:
        content = f.read().strip()

    expected_content = "x,y\n1.0,3.2\n2.0,5.1\n3.0,6.8\n4.0,9.1\n5.0,10.9"
    assert content == expected_content, f"Content of {dataset_path} is incorrect."


def test_c_source_exists():
    """Check that the C source file exists."""
    c_source_path = "/home/user/fit_model.c"
    assert os.path.isfile(c_source_path), f"File {c_source_path} does not exist."


def test_solution_txt():
    """Check that solution.txt exists and contains the correct values."""
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(solution_path), f"File {solution_path} does not exist."

    with open(solution_path, "r") as f:
        content = f.read()

    assert_expected_values(content)


def test_compile_and_run_c_program():
    """Compile the submitted C source and verify its actual standard output."""
    source_path = "/home/user/fit_model.c"
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(source_path), f"File {source_path} does not exist."
    assert os.path.isfile(solution_path), f"File {solution_path} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        executable = os.path.join(tmpdir, "fit_model")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", source_path, "-lm", "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, \
            f"fit_model.c failed to compile:\n{compile_result.stderr}"

        run_result = subprocess.run(
            [executable],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert run_result.returncode == 0, \
            f"Compiled program failed with code {run_result.returncode}:\n{run_result.stderr}"

    # The program itself must produce exactly the required two output lines.
    assert len(run_result.stdout.strip().split('\n')) == 2, \
        "Compiled program must output exactly two lines."
    assert_expected_values(run_result.stdout)

    # solution.txt must be the saved standard output of the submitted program.
    with open(solution_path, "r") as f:
        saved_output = f.read()
    assert saved_output.strip() == run_result.stdout.strip(), \
        "solution.txt does not match the compiled program's standard output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
