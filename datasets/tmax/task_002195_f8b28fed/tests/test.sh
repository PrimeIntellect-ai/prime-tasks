#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import math
import os
import re
import secrets
import subprocess

ARTIFACTS_PATH = "/home/user/artifacts.csv"
EMBEDDINGS_PATH = "/home/user/embeddings.tsv"
OUTPUT_PATH = "/home/user/best_run.txt"
SCRIPT_PATH = "/home/user/find_best_run.sh"
QUERY_VECTOR = [0.1, 0.5, 0.2, -0.1, 0.8]


def expected_result(artifacts_text, embeddings_text):
    efficiencies = []
    reader = csv.DictReader(io.StringIO(artifacts_text))
    for row in reader:
        efficiency = float(row["accuracy"]) / float(row["training_time"])
        efficiencies.append((row["run_id"], efficiency))

    efficiencies.sort(key=lambda x: x[1], reverse=True)
    top_5_runs = {x[0] for x in efficiencies[:5]}

    best_run_id = None
    max_dot_product = -float("inf")
    for line in embeddings_text.splitlines():
        parts = line.strip().split("|")
        if len(parts) < 6 or parts[0] not in top_5_runs:
            continue
        vector = [float(x) for x in parts[1:6]]
        dot_product = sum(a * b for a, b in zip(vector, QUERY_VECTOR))
        if dot_product > max_dot_product:
            max_dot_product = dot_product
            best_run_id = parts[0]

    return best_run_id, max_dot_product


def assert_output(artifacts_text, embeddings_text):
    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"
    with open(OUTPUT_PATH, "r") as f:
        actual_output = f.read().strip()

    parts = actual_output.split(",")
    assert len(parts) == 2, (
        f"Output in {OUTPUT_PATH} must be in format 'run_id,dot_product', "
        f"got '{actual_output}'"
    )
    actual_run_id = parts[0].strip()
    actual_dot_product = float(parts[1].strip())
    best_run_id, max_dot_product = expected_result(artifacts_text, embeddings_text)

    assert actual_run_id == best_run_id, (
        f"Expected best run_id '{best_run_id}', but got '{actual_run_id}'"
    )
    assert math.isclose(actual_dot_product, max_dot_product,
                        rel_tol=1e-5, abs_tol=1e-5), (
        f"Expected dot product {max_dot_product}, but got {actual_dot_product}"
    )


def run_case(artifacts_text, embeddings_text, original_script):
    with open(ARTIFACTS_PATH, "w") as f:
        f.write(artifacts_text)
    with open(EMBEDDINGS_PATH, "w") as f:
        f.write(embeddings_text)
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        ["bash", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )

    with open(ARTIFACTS_PATH, "r") as f:
        assert f.read() == artifacts_text, "The script must not modify artifacts.csv"
    with open(EMBEDDINGS_PATH, "r") as f:
        assert f.read() == embeddings_text, "The script must not modify embeddings.tsv"
    with open(SCRIPT_PATH, "rb") as f:
        assert f.read() == original_script, "The script modified itself while running"

    assert_output(artifacts_text, embeddings_text)


def make_random_case():
    rng = secrets.SystemRandom()
    suffix = secrets.token_hex(5)
    rows = []
    embeddings = []
    for i in range(10):
        run_id = f"trial_{suffix}_{i}"
        accuracy = rng.uniform(0.55, 0.995)
        training_time = rng.uniform(15.0, 240.0)
        loss = rng.uniform(0.001, 0.4)
        rows.append(
            f"{run_id},model_{i},{accuracy:.9f},{loss:.9f},{training_time:.9f}"
        )
        vector = [rng.uniform(-1.5, 1.5) for _ in range(5)]
        embeddings.append(run_id + "|" + "|".join(f"{x:.9f}" for x in vector))

    artifacts_text = (
        "run_id,model_name,accuracy,loss,training_time\n"
        + "\n".join(rows) + "\n"
    )
    embeddings_text = "\n".join(embeddings) + "\n"
    return artifacts_text, embeddings_text


def test_best_run_computation():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "rb") as f:
        original_script = f.read()
    assert original_script.strip(), "The Bash script is empty"

    syntax = subprocess.run(
        ["bash", "-n", SCRIPT_PATH], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert syntax.returncode == 0, f"Invalid Bash syntax: {syntax.stderr}"

    source = original_script.decode("utf-8", errors="replace")
    source_without_comment_lines = "\n".join(
        line for line in source.splitlines()
        if not line.lstrip().startswith("#")
    )
    forbidden = re.compile(
        r"(?:^\s*|[;&|]\s*|\$\(\s*|\b(?:if|while|until|then|do|else)\s+)"
        r"(?:command\s+|exec\s+|env(?:\s+\w+=\S+)*\s+)?"
        r"(?:/[^\s;|]+/)?(?:python(?:[0-9.]*)?|rscript|ruby|perl|node(?:js)?|php|lua|R)"
        r"(?=\s|$)",
        re.MULTILINE | re.IGNORECASE,
    )
    assert not forbidden.search(source_without_comment_lines), (
        "The solution must use Bash and standard Linux utilities, not another "
        "scripting-language interpreter"
    )

    with open(ARTIFACTS_PATH, "r") as f:
        original_artifacts = f.read()
    with open(EMBEDDINGS_PATH, "r") as f:
        original_embeddings = f.read()

    try:
        # Execute and check the original supplied fixture.
        run_case(original_artifacts, original_embeddings, original_script)

        # Exercise the submitted script on unseen fixtures so a precomputed output
        # cannot satisfy the verifier.
        for _ in range(3):
            artifacts_text, embeddings_text = make_random_case()
            run_case(artifacts_text, embeddings_text, original_script)

        # Leave the requested output corresponding to the original input files.
        run_case(original_artifacts, original_embeddings, original_script)
    finally:
        with open(ARTIFACTS_PATH, "w") as f:
            f.write(original_artifacts)
        with open(EMBEDDINGS_PATH, "w") as f:
            f.write(original_embeddings)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
