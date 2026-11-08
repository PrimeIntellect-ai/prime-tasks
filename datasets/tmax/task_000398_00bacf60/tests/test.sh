#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
from pathlib import Path

C_FILE = Path("/home/user/clean_and_search.c")
DATA_FILE = Path("/home/user/embeddings.csv")
RESULT_FILE = Path("/home/user/result.txt")
BINARY = Path("/tmp/clean_and_search_verified")


def test_c_file_exists():
    c_file_path = "/home/user/clean_and_search.c"
    assert os.path.isfile(c_file_path), f"The C source file is missing at {c_file_path}. You must write your program to this location."


def test_result_file_exists_and_correct():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"The output file is missing at {result_path}. Did you run your program and save the output?"

    with open(result_path, "r") as f:
        content = f.read().strip()

    expected = "38, 45, 68, 86"
    assert expected in content, f"The result file {result_path} contains incorrect output. Expected it to contain '{expected}', but found '{content}'."


def load_data(path):
    rows = []
    with open(path, "r") as f:
        for line in f:
            fields = line.strip().split(",")
            assert len(fields) == 5
            rows.append([float(x) if x != "NaN" else math.nan for x in fields])
    assert len(rows) == 100
    return rows


def expected_output(rows, k):
    cleaned = [row[:] for row in rows]
    means = []
    for col in range(5):
        values = [row[col] for row in cleaned if not math.isnan(row[col])]
        means.append(sum(values) / len(values))

    for row in cleaned:
        for col in range(5):
            if math.isnan(row[col]):
                row[col] = means[col]

    sigmas = []
    for col in range(5):
        variance = sum((row[col] - means[col]) ** 2 for row in cleaned) / 100.0
        sigmas.append(math.sqrt(variance))

    for row in cleaned:
        for col in range(5):
            lower = means[col] - 2.0 * sigmas[col]
            upper = means[col] + 2.0 * sigmas[col]
            row[col] = min(upper, max(lower, row[col]))

    fold_size = 100 // k
    query = [sum(cleaned[r][col] for r in range(fold_size)) / fold_size for col in range(5)]
    answers = []
    for fold in range(1, k):
        start = fold * fold_size
        end = start + fold_size
        best_index = min(
            range(start, end),
            key=lambda r: sum((cleaned[r][col] - query[col]) ** 2 for col in range(5)),
        )
        answers.append(str(best_index))
    return ", ".join(answers)


def assert_exact_text(actual, expected, location):
    assert actual in (expected, expected + "\n"), (
        f"Incorrect {location}. Expected exactly '{expected}' with an optional final newline, "
        f"but found {actual!r}."
    )


def run_and_check(k, rows):
    expected = expected_output(rows, k)
    completed = subprocess.run(
        [str(BINARY), str(k)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"Program exited with status {completed.returncode} for K={k}. stderr: {completed.stderr}"
    )
    assert_exact_text(completed.stdout, expected, f"stdout for K={k}")
    assert RESULT_FILE.is_file(), f"Program did not create {RESULT_FILE} for K={k}."
    assert_exact_text(RESULT_FILE.read_text(), expected, f"{RESULT_FILE} for K={k}")


def make_random_dataset():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    rows = [[rng.uniform(-8.0, 12.0) for _ in range(5)] for _ in range(100)]
    for col in range(5):
        for row in rng.sample(range(100), 3):
            rows[row][col] = math.nan
    for col in range(5):
        row = rng.randrange(100)
        rows[row][col] = rng.choice((-1.0, 1.0)) * rng.uniform(60.0, 100.0)

    lines = []
    for row in rows:
        lines.append(",".join("NaN" if math.isnan(x) else f"{x:.9f}" for x in row))
    text = "\n".join(lines) + "\n"
    DATA_FILE.write_text(text)
    return load_data(DATA_FILE)


def test_program_compiles_and_implements_pipeline_for_multiple_k_values():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-o", str(BINARY), str(C_FILE), "-lm"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"C program failed to compile: {compile_result.stderr}"
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), "Compilation did not produce an executable."

    original_data = DATA_FILE.read_bytes()
    try:
        original_rows = load_data(DATA_FILE)
        for k in (2, 4, 5, 10, 20, 25, 50, 100):
            run_and_check(k, original_rows)

        randomized_rows = make_random_dataset()
        for k in (4, 5, 10, 20):
            run_and_check(k, randomized_rows)
    finally:
        DATA_FILE.write_bytes(original_data)
        if BINARY.exists():
            subprocess.run(
                [str(BINARY), "5"], cwd="/home/user", stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, timeout=10, check=False
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
