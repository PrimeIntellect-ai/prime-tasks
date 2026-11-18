#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

SOURCE_PATH = "/home/user/etl_infer.c"
EXECUTABLE_PATH = "/home/user/etl_infer"
DATASET_PATH = "/home/user/dataset.csv"
OUTPUT_PATH = "/home/user/best_model.txt"


def test_c_source_code_exists():
    assert os.path.isfile(SOURCE_PATH), f"The C source code file {SOURCE_PATH} does not exist."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"The executable file {EXECUTABLE_PATH} does not exist."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"The file {EXECUTABLE_PATH} is not executable."


def test_best_model_output():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected = "Model: 2, MSE: 1.3225"
    assert content == expected, f"The content of {OUTPUT_PATH} is incorrect. Expected '{expected}', got '{content}'."


def prediction(model, x):
    if model == 1:
        return 1.5 + 2.0 * x
    if model == 2:
        return -0.5 + 1.2 * x + 0.5 * x * x
    return -0.5 + 1.2 * x + 0.5 * x * x - 0.1 * x * x * x


def expected_output(rows):
    mses = []
    for model in (1, 2, 3):
        mse = sum((y - prediction(model, x)) ** 2 for x, y in rows) / len(rows)
        mses.append(mse)
    best = min(range(3), key=lambda i: mses[i])
    return f"Model: {best + 1}, MSE: {mses[best]:.4f}"


def run_case(valid_rows, corrupt_rows):
    with open(DATASET_PATH, "w", encoding="utf-8", newline="") as f:
        f.write("id,x,y\n")
        row_id = 1
        for x, y in valid_rows:
            f.write(f"{row_id},{x:.6f},{y:.6f}\n")
            row_id += 1
        for x_text, y_text in corrupt_rows:
            f.write(f"{row_id},{x_text},{y_text}\n")
            row_id += 1

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [EXECUTABLE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"etl_infer exited with {result.returncode}. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT_PATH), "Running etl_infer did not create best_model.txt."

    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        actual = f.read().strip()

    parsed_rows = [(float(f"{x:.6f}"), float(f"{y:.6f}")) for x, y in valid_rows]
    expected = expected_output(parsed_rows)
    assert re.fullmatch(r"Model: [123], MSE: -?\d+\.\d{4}", actual), (
        f"Output has the wrong format: {actual!r}"
    )
    assert actual == expected, f"Expected {expected!r}, got {actual!r}."


def test_compile_and_execute_etl_implementation():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE_PATH, "-o", EXECUTABLE_PATH, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"The C source did not compile. stdout={compile_result.stdout!r}, stderr={compile_result.stderr!r}"
    )
    assert os.path.isfile(EXECUTABLE_PATH) and os.access(EXECUTABLE_PATH, os.X_OK)

    rng = random.SystemRandom()
    corrupt_rows = [
        ("", "9999.0"),
        ("NaN", "-9999.0"),
        ("abc", "1234.0"),
        ("1.25junk", "8888.0"),
        ("2.0", ""),
        ("-3.0", "NaN"),
        ("4.0", "not-a-number"),
    ]

    for target_model in (1, 2, 3):
        valid_rows = []
        for _ in range(9):
            x = rng.uniform(-4.5, 4.5)
            noise = rng.uniform(-0.08, 0.08)
            y = prediction(target_model, x) + noise
            valid_rows.append((x, y))
        run_case(valid_rows, corrupt_rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
