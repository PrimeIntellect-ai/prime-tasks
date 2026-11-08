#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import subprocess
import uuid

SRC_PATH = "/home/user/artifact_tracker.cpp"
OUTPUT_PATH = "/home/user/best_experiment.txt"
EXPERIMENTS_PATH = "/home/user/data/experiments.csv"
EMBEDDINGS_PATH = "/home/user/data/embeddings.csv"
BINARY_PATH = "/tmp/artifact_tracker_verified"


def test_cpp_source_exists():
    """Verify that the C++ source file was created."""
    assert os.path.isfile(SRC_PATH), f"The C++ source file {SRC_PATH} was not found."


def test_output_file_exists_and_content():
    """Preserve the original check for the supplied datasets."""
    assert os.path.isfile(OUTPUT_PATH), (
        f"The output file {OUTPUT_PATH} does not exist. Did you compile and run the C++ program?"
    )

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    expected = "Closest Exp: e2, Distance: 0.1414, Acc_Test_Pass: false"
    assert content == expected, (
        f"Output file content mismatch.\nExpected: '{expected}'\nGot: '{content}'"
    )


def _expected(experiments, embeddings):
    scores = {exp_id: (validation, test) for exp_id, validation, test in experiments}
    joined = []
    for exp_id, v1, v2, v3 in embeddings:
        if exp_id in scores:
            distance = math.sqrt(
                (v1 - 0.5) ** 2 + (v2 - 0.5) ** 2 + (v3 - 0.5) ** 2
            )
            joined.append((distance, exp_id))

    assert joined, "Verifier test case must contain at least one joined row"
    distance, exp_id = min(joined)
    validation, test = scores[exp_id]
    passed = abs(validation - test) <= 1e-4
    return (
        f"Closest Exp: {exp_id}, Distance: {distance:.4f}, "
        f"Acc_Test_Pass: {'true' if passed else 'false'}"
    )


def _write_case(experiments, embeddings):
    with open(EXPERIMENTS_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["exp_id", "validation_score", "test_score"])
        writer.writerows(experiments)

    with open(EMBEDDINGS_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["exp_id", "v1", "v2", "v3"])
        writer.writerows(embeddings)


def test_compile_and_execute_on_additional_inputs():
    """Compile the submission and exercise parsing, joining, distance, and tolerance logic."""
    compile_result = subprocess.run(
        ["g++", "-std=c++17", SRC_PATH, "-o", BINARY_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "artifact_tracker.cpp did not compile with g++ -std=c++17:\n"
        + compile_result.stderr
    )

    original_experiments = open(EXPERIMENTS_PATH, "rb").read()
    original_embeddings = open(EMBEDDINGS_PATH, "rb").read()
    original_output = open(OUTPUT_PATH, "rb").read() if os.path.exists(OUTPUT_PATH) else None

    token = uuid.uuid4().hex
    a, b, c, d, unmatched = [f"{name}_{token}" for name in "abcdu"]
    cases = [
        (
            [
                (a, 0.8100, 0.8103),
                (c, 0.4400, 0.4400),
                (b, 0.6250, 0.6249),
            ],
            [
                (unmatched, 0.5, 0.5, 0.5),
                (c, 0.7, 0.7, 0.7),
                (b, 0.52, 0.47, 0.51),
                (a, 0.1, 0.2, 0.1),
            ],
        ),
        (
            [
                (d, 0.90021, 0.90000),
                (a, 0.30000, 0.30000),
                (b, 0.75000, 0.75005),
                (unmatched, 0.10000, 0.10000),
            ],
            [
                (b, 0.35, 0.61, 0.56),
                (a, 0.9, 0.9, 0.9),
                (d, 0.49, 0.52, 0.48),
            ],
        ),
    ]

    try:
        for experiments, embeddings in cases:
            expected = _expected(experiments, embeddings)
            _write_case(experiments, embeddings)

            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)

            # Redirecting stdout also supports implementations that emit the required
            # line to stdout, while implementations that directly write the hardcoded
            # output path continue to work.
            with open(OUTPUT_PATH, "w") as output_stream:
                run_result = subprocess.run(
                    [BINARY_PATH],
                    cwd="/home/user",
                    stdin=subprocess.DEVNULL,
                    stdout=output_stream,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )

            assert run_result.returncode == 0, (
                f"Compiled program exited with status {run_result.returncode}:\n"
                + run_result.stderr
            )
            assert os.path.isfile(OUTPUT_PATH), "Program did not produce best_experiment.txt"

            with open(OUTPUT_PATH, "r") as f:
                actual = f.read().strip()
            assert actual == expected, (
                f"Program produced an incorrect result for verifier-generated data.\n"
                f"Expected: '{expected}'\nGot: '{actual}'"
            )
    finally:
        with open(EXPERIMENTS_PATH, "wb") as f:
            f.write(original_experiments)
        with open(EMBEDDINGS_PATH, "wb") as f:
            f.write(original_embeddings)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
