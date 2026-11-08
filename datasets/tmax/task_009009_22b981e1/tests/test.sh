#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess

PROJECT = "/home/user/project"
CSV_PATH = os.path.join(PROJECT, "embeddings.csv")
C_PATH = os.path.join(PROJECT, "compute_correlation.c")
OUT_PATH = os.path.join(PROJECT, "top_pair.txt")
BIN_PATH = "/tmp/compute_correlation_verified"


def expected_output(vecs):
    max_corr = -2.0
    best_i = -1
    best_j = -1

    for i in range(len(vecs)):
        for j in range(i + 1, len(vecs)):
            v1 = vecs[i]
            v2 = vecs[j]
            mean1 = sum(v1) / len(v1)
            mean2 = sum(v2) / len(v2)
            cov = sum((x - mean1) * (y - mean2) for x, y in zip(v1, v2))
            var1 = sum((x - mean1) ** 2 for x in v1)
            var2 = sum((y - mean2) ** 2 for y in v2)
            corr = 0.0 if var1 * var2 == 0 else cov / math.sqrt(var1 * var2)
            if corr > max_corr:
                max_corr = corr
                best_i = i
                best_j = j

    return f"{best_i},{best_j},{max_corr:.4f}"


def read_embeddings(path):
    vecs = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                vecs.append([float(x) for x in line.split(",")])
    return vecs


def run_program():
    if os.path.lexists(OUT_PATH):
        os.remove(OUT_PATH)
    result = subprocess.run(
        [BIN_PATH], cwd=PROJECT, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled C program exited with status {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert os.path.isfile(OUT_PATH), "The executed C program did not create top_pair.txt."
    with open(OUT_PATH, "r") as f:
        return f.read().strip()


def make_hidden_embeddings():
    rng = random.SystemRandom()
    while True:
        base = [rng.randint(-30, 30) for _ in range(4)]
        if len(set(base)) < 3:
            continue
        mate = [3 * x + 7 for x in base]
        others = [[rng.randint(-40, 40) for _ in range(4)] for _ in range(3)]
        if any(len(set(v)) < 2 for v in others):
            continue
        tagged = [(base, "pair"), (mate, "pair")] + [(v, "other") for v in others]
        rng.shuffle(tagged)
        vecs = [v for v, _ in tagged]
        pair_indices = [i for i, (_, tag) in enumerate(tagged) if tag == "pair"]
        if expected_output(vecs).startswith(f"{pair_indices[0]},{pair_indices[1]},"):
            return vecs


def test_compiles_and_executes_c_program_on_derived_inputs():
    assert os.path.isfile(C_PATH), f"The file {C_PATH} is missing."
    compile_result = subprocess.run(
        ["gcc", "-std=c11", C_PATH, "-lm", "-o", BIN_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        "compute_correlation.c did not compile successfully with GCC and libm. "
        f"stderr: {compile_result.stderr}"
    )

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    try:
        hidden_vecs = make_hidden_embeddings()
        with open(CSV_PATH, "w") as f:
            for vec in hidden_vecs:
                f.write(", ".join(str(x) for x in vec) + "\n")

        actual = run_program()
        expected = expected_output(hidden_vecs)
        assert actual == expected, (
            "The compiled C program produced an incorrect result on verifier-generated "
            f"embeddings. Expected '{expected}', but found '{actual}'."
        )
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        # Run once more on the supplied input so top_pair.txt must be produced by
        # the compiled submission and is left in the required final state.
        run_program()


def test_top_pair_txt_exists_and_correct():
    csv_path = "/home/user/project/embeddings.csv"
    out_path = "/home/user/project/top_pair.txt"

    assert os.path.isfile(csv_path), f"The file {csv_path} is missing."
    assert os.path.isfile(out_path), f"The file {out_path} is missing. Did you run the compiled C program?"

    # Read the embeddings and recompute the expected result
    vecs = []
    with open(csv_path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                vecs.append([float(x) for x in line.split(",")])

    assert len(vecs) > 1, "Not enough vectors in embeddings.csv to compute correlation."

    max_corr = -2.0
    best_i = -1
    best_j = -1

    for i in range(len(vecs)):
        for j in range(i + 1, len(vecs)):
            v1 = vecs[i]
            v2 = vecs[j]

            mean1 = sum(v1) / len(v1)
            mean2 = sum(v2) / len(v2)

            cov = sum((x - mean1) * (y - mean2) for x, y in zip(v1, v2))
            var1 = sum((x - mean1)**2 for x in v1)
            var2 = sum((y - mean2)**2 for y in v2)

            if var1 * var2 == 0:
                corr = 0.0
            else:
                corr = cov / math.sqrt(var1 * var2)

            if corr > max_corr:
                max_corr = corr
                best_i = i
                best_j = j

    expected = f"{best_i},{best_j},{max_corr:.4f}"

    with open(out_path, "r") as f:
        actual = f.read().strip()

    assert actual == expected, (
        f"Incorrect output in top_pair.txt. Expected '{expected}', but found '{actual}'."
    )


def test_c_code_fixed():
    c_path = "/home/user/project/compute_correlation.c"
    assert os.path.isfile(c_path), f"The file {c_path} is missing."

    with open(c_path, "r") as f:
        content = f.read()

    # The original buggy code used integer arithmetic for sum_i and sum_j
    assert "int sum_i = 0, sum_j = 0;" not in content, (
        "The C code still contains the integer arithmetic bug for sum_i and sum_j. "
        "These should be floats to prevent truncation."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
