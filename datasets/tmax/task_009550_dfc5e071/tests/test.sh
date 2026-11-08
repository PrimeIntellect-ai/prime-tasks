#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile


def pearson(pairs):
    x = [a for a, _ in pairs]
    y = [b for _, b in pairs]
    n = len(x)
    assert n > 0
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    cov = sum((xi - mean_x) * (yi - mean_y) for xi, yi in pairs)
    var_x = sum((xi - mean_x) ** 2 for xi in x)
    var_y = sum((yi - mean_y) ** 2 for yi in y)
    return cov / math.sqrt(var_x * var_y)


def run_and_check(program, pairs):
    # Render first, then derive the answer from the exact values supplied on stdin.
    lines = [f"{x:.10f} {y:.10f}" for x, y in pairs]
    supplied = [tuple(map(float, line.split())) for line in lines]
    expected = f"{pearson(supplied):.4f}\n"
    proc = subprocess.run(
        [program],
        input=("\n".join(lines) + "\n").encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert proc.returncode == 0, (
        f"{program} exited with status {proc.returncode}; "
        f"stderr={proc.stderr.decode(errors='replace')!r}"
    )
    actual = proc.stdout.decode(errors="replace")
    assert re.fullmatch(r"-?\d+\.\d{4}\n", actual), (
        f"Output must be exactly one number with four decimal places and a newline; got {actual!r}."
    )
    assert actual == expected, f"Expected {expected!r}, but {program} produced {actual!r}."


def dynamic_cases():
    rng = secrets.SystemRandom()
    cases = []
    for slope, count in [
        (0.73, rng.randrange(19, 43)),
        (-1.31, rng.randrange(47, 83)),
        (0.18, rng.randrange(101, 181)),
    ]:
        pairs = []
        for _ in range(count):
            x = rng.uniform(-25.0, 25.0)
            noise = rng.uniform(-6.0, 6.0)
            y = slope * x + noise
            pairs.append((x, y))
        cases.append(pairs)
    return cases


def test_corr_c_exists():
    path = "/home/user/corr.c"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a regular file."
    with open(path, "r") as f:
        content = f.read()
    assert len(content.strip()) > 0, f"{path} is empty."


def test_corr_executable_exists():
    path = "/home/user/corr"
    assert os.path.exists(path), f"Executable {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a regular file."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_installed_corr_handles_dynamic_stdin():
    for pairs in dynamic_cases():
        run_and_check("/home/user/corr", pairs)


def test_corr_source_builds_and_handles_dynamic_stdin():
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "corr")
        proc = subprocess.run(
            ["gcc", "-std=c11", "-O2", "/home/user/corr.c", "-lm", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert proc.returncode == 0, (
            "corr.c did not compile successfully: " + proc.stderr.decode(errors="replace")
        )
        for pairs in dynamic_cases():
            run_and_check(rebuilt, pairs)


def test_result_txt():
    dataset_path = "/home/user/dataset.tsv"
    result_path = "/home/user/result.txt"

    assert os.path.exists(dataset_path), f"Dataset {dataset_path} is missing."
    assert os.path.exists(result_path), f"Result file {result_path} does not exist."

    # Calculate the expected correlation using standard library
    x = []
    y = []
    with open(dataset_path, "r") as f:
        for line in f:
            parts = line.strip("\n").split("\t")
            if len(parts) >= 4:
                x.append(float(parts[1]))
                y.append(float(parts[3]))

    n = len(x)
    assert n > 0, "Dataset is empty."

    mean_x = sum(x) / n
    mean_y = sum(y) / n

    cov = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    var_x = sum((xi - mean_x) ** 2 for xi in x)
    var_y = sum((yi - mean_y) ** 2 for yi in y)

    corr = cov / math.sqrt(var_x * var_y)
    expected_result = f"{corr:.4f}"

    with open(result_path, "r") as f:
        actual_result = f.read().strip()

    assert actual_result == expected_result, f"Expected result {expected_result}, but got {actual_result} in {result_path}."

    # Also execute the submitted binary on the columns from the real dataset.
    dataset_input = "".join(f"{xi} {yi}\n" for xi, yi in zip(x, y)).encode()
    proc = subprocess.run(
        ["/home/user/corr"],
        input=dataset_input,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert proc.returncode == 0, f"corr failed on dataset input: {proc.stderr.decode(errors='replace')!r}"
    assert proc.stdout.decode(errors="replace") == expected_result + "\n", (
        "The submitted corr executable does not produce result.txt's expected value from the dataset columns."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
