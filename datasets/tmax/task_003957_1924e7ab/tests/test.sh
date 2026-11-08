#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import math
import os
import random
import secrets
import subprocess
import tarfile

import pytest

PIPELINE = "/home/user/pipeline.sh"
RAW_DATA = "/home/user/raw_data/user_features.csv"
TOP_OUTPUT = "/home/user/output/top_similar.txt"
CORR_OUTPUT = "/home/user/output/correlation.txt"
ARCHIVE = "/home/user/archive/data_archive.tar.gz"


def run_pipeline():
    return subprocess.run(
        ["/bin/bash", PIPELINE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=300,
        check=False,
    )


def archive_contains_exact_raw_data(expected_bytes):
    with tarfile.open(ARCHIVE, "r:gz") as tar:
        for member in tar.getmembers():
            if member.isfile() and os.path.basename(member.name) == "user_features.csv":
                extracted = tar.extractfile(member)
                if extracted is not None and extracted.read() == expected_bytes:
                    return True
    return False


def cosine(a, b):
    numerator = sum(x * y for x, y in zip(a, b))
    denominator = math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b))
    return numerator / denominator


def pearson(xs, ys):
    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    denominator = math.sqrt(sum((x - mean_x) ** 2 for x in xs) * sum((y - mean_y) ** 2 for y in ys))
    return numerator / denominator


def test_pipeline_script_exists():
    assert os.path.isfile("/home/user/pipeline.sh"), "The pipeline script /home/user/pipeline.sh does not exist."
    assert os.access("/home/user/pipeline.sh", os.X_OK), "The pipeline script /home/user/pipeline.sh is not executable."


def test_pipeline_executes_successfully():
    result = run_pipeline()
    assert result.returncode == 0, f"pipeline.sh failed. stdout: {result.stdout}\nstderr: {result.stderr}"


def test_top_similar_output():
    output_path = "/home/user/output/top_similar.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_users = ["U005", "U002", "U004"]
    assert lines == expected_users, f"Expected top similar users to be {expected_users}, but got {lines}."


def test_correlation_output():
    output_path = "/home/user/output/correlation.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    with open(output_path, "r") as f:
        content = f.read().strip()

    assert content == "-0.806", f"Expected correlation to be '-0.806', but got '{content}'."


def test_archive_exists_and_valid():
    archive_path = "/home/user/archive/data_archive.tar.gz"
    assert os.path.isfile(archive_path), f"The archive file {archive_path} does not exist."

    assert tarfile.is_tarfile(archive_path), f"The file {archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getnames()
        # Preserve the original member-name assertion.
        found = any("user_features.csv" in member for member in members)
        assert found, f"The archive {archive_path} does not contain 'user_features.csv'. Members found: {members}"

    with open(RAW_DATA, "rb") as f:
        raw_bytes = f.read()
    assert archive_contains_exact_raw_data(raw_bytes), "The archive does not contain the actual raw user_features.csv as a regular file."


def test_pipeline_computes_results_for_unseen_input():
    with open(RAW_DATA, "rb") as f:
        original_raw = f.read()

    rng = random.Random(secrets.randbits(128))
    suffix = secrets.token_hex(4).upper()
    rows = []
    target = [round(rng.uniform(4.0, 16.0), 6) for _ in range(3)]
    rows.append(("U001", *target))

    for i in range(1, 10):
        f1 = round(rng.uniform(2.0, 22.0), 6)
        f2 = round(26.0 - f1 + rng.uniform(-3.0, 3.0), 6)
        f3 = round(rng.uniform(0.5, 18.0), 6)
        rows.append((f"X{suffix}_{i}", f1, f2, f3))

    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(["user_id", "f1", "f2", "f3"])
    writer.writerows(rows)
    generated_raw = buffer.getvalue().encode("utf-8")

    similarities = [
        (row[0], cosine(target, [row[1], row[2], row[3]]))
        for row in rows[1:]
    ]
    expected_users = [user_id for user_id, _ in sorted(similarities, key=lambda item: item[1], reverse=True)[:3]]
    expected_correlation = f"{pearson([r[1] for r in rows], [r[2] for r in rows]):.3f}"

    try:
        with open(RAW_DATA, "wb") as f:
            f.write(generated_raw)

        result = run_pipeline()
        assert result.returncode == 0, f"pipeline.sh failed on generated input. stdout: {result.stdout}\nstderr: {result.stderr}"

        assert os.path.isfile(TOP_OUTPUT), f"The output file {TOP_OUTPUT} does not exist after rerunning the pipeline."
        with open(TOP_OUTPUT, "r") as f:
            actual_users = [line.strip() for line in f if line.strip()]
        assert actual_users == expected_users, f"Expected generated-input similarities {expected_users}, got {actual_users}."

        assert os.path.isfile(CORR_OUTPUT), f"The output file {CORR_OUTPUT} does not exist after rerunning the pipeline."
        with open(CORR_OUTPUT, "r") as f:
            actual_correlation = f.read().strip()
        assert actual_correlation == expected_correlation, f"Expected generated-input correlation {expected_correlation}, got {actual_correlation}."

        assert os.path.isfile(ARCHIVE), f"The archive file {ARCHIVE} does not exist after rerunning the pipeline."
        assert tarfile.is_tarfile(ARCHIVE), f"The file {ARCHIVE} is not a valid tar archive after rerunning the pipeline."
        assert archive_contains_exact_raw_data(generated_raw), "The archive does not contain the generated raw CSV with its exact contents."
    finally:
        with open(RAW_DATA, "wb") as f:
            f.write(original_raw)
        cleanup = run_pipeline()
        assert cleanup.returncode == 0, f"pipeline.sh failed when restoring final outputs. stdout: {cleanup.stdout}\nstderr: {cleanup.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
