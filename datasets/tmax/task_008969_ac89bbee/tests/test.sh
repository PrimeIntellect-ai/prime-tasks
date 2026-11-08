#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import subprocess

import pytest

HOME = "/home/user"
INPUT = f"{HOME}/input/features.csv"
OUTPUT = f"{HOME}/output"
RUN_SH = f"{HOME}/run.sh"
PIPELINE = f"{HOME}/pipeline"

ORIGINAL_FIXTURE = """id,f1,f2,f3,f4,f5
1,1.5,2.0,NaN,4.1,5.0
2,1.6,2.0,0.0,4.1,5.1
3,10.0,10.0,10.0,10.0,10.0
4,1.5,2.0,0.0,4.1,5.0
invalid_id,1.0,2.0,3.0,4.0,5.0
5,10.1,10.0,10.0,10.0,10.0
6,0.0,0.0,0.0,0.0,0.0
7,NaN,NaN,NaN,NaN,NaN
"""


def execute_run_sh():
    os.makedirs(OUTPUT, exist_ok=True)
    for name in ("pipeline", "recommendations.csv", "run1.csv", "run2.csv", "checksum.txt"):
        path = f"{HOME}/{name}" if name == "pipeline" else f"{OUTPUT}/{name}"
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["bash", RUN_SH],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"run.sh failed:\n{result.stdout}"


def read_output_lines():
    path = f"{OUTPUT}/recommendations.csv"
    assert os.path.isfile(path), f"The file {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def verify_checksum_and_cleanup():
    checksum_path = f"{OUTPUT}/checksum.txt"
    recs_path = f"{OUTPUT}/recommendations.csv"
    assert os.path.isfile(checksum_path), f"The file {checksum_path} does not exist."
    assert os.path.isfile(recs_path), f"The file {recs_path} does not exist."

    with open(recs_path, "rb") as f:
        expected_hash = hashlib.sha256(f.read()).hexdigest()
    with open(checksum_path, "r", encoding="utf-8") as f:
        checksum_content = f.read().strip()

    assert checksum_content.startswith(expected_hash), f"{checksum_path} does not contain the correct SHA256 hash."
    assert "run1.csv" in checksum_content, f"{checksum_path} does not seem to have been generated from 'run1.csv'."
    assert not os.path.exists(f"{OUTPUT}/run1.csv"), "run1.csv was not moved back to recommendations.csv."
    assert not os.path.exists(f"{OUTPUT}/run2.csv"), "run2.csv was not deleted."


def expected_lines(records):
    parsed = []
    for user_id, feature_tokens in records:
        features = [0.0 if token == "NaN" else float(token) for token in feature_tokens]
        parsed.append((user_id, features))

    result = ["id,nearest_neighbor_id"]
    for user_id, features in sorted(parsed):
        candidates = []
        for other_id, other_features in parsed:
            if other_id == user_id:
                continue
            distance_squared = sum((a - b) ** 2 for a, b in zip(features, other_features))
            candidates.append((distance_squared, other_id))
        nearest = min(candidates, key=lambda item: (item[0], item[1]))[1]
        result.append(f"{user_id},{nearest}")
    return result


def run_generated_case(records, malformed_rows):
    rows = [f"{user_id}," + ",".join(features) for user_id, features in records]
    rows.extend(malformed_rows)
    secrets.SystemRandom().shuffle(rows)
    with open(INPUT, "w", encoding="utf-8", newline="") as f:
        f.write("id,f1,f2,f3,f4,f5\n")
        f.write("\n".join(rows) + "\n")

    execute_run_sh()
    assert read_output_lines() == expected_lines(records)
    verify_checksum_and_cleanup()
    assert os.path.isfile(PIPELINE)
    assert os.access(PIPELINE, os.X_OK), "The compiled pipeline is not executable."
    with open(PIPELINE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pipeline is not a compiled executable."


def test_00_execute_run_sh_on_original_fixture():
    assert os.path.isfile(f"{HOME}/pipeline.c"), "The source file /home/user/pipeline.c does not exist."
    assert os.path.isfile(RUN_SH), "The script /home/user/run.sh does not exist."
    os.makedirs(f"{HOME}/input", exist_ok=True)
    with open(INPUT, "w", encoding="utf-8", newline="") as f:
        f.write(ORIGINAL_FIXTURE)
    execute_run_sh()


def test_pipeline_files_exist():
    assert os.path.isfile("/home/user/pipeline.c"), "The source file /home/user/pipeline.c does not exist."
    assert os.path.isfile("/home/user/run.sh"), "The script /home/user/run.sh does not exist."
    assert os.path.isfile("/home/user/pipeline"), "The compiled executable /home/user/pipeline does not exist."


def test_recommendations_csv_content():
    file_path = "/home/user/output/recommendations.csv"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    expected = [
        "id,nearest_neighbor_id",
        "1,4",
        "2,1",
        "3,5",
        "4,1",
        "5,3",
        "6,7",
        "7,6",
    ]
    assert read_output_lines() == expected, f"The contents of {file_path} do not match the expected recommendations."


def test_checksum_file():
    verify_checksum_and_cleanup()


def test_dynamic_ties_nan_invalid_ids_and_sorting():
    records = [
        (10, ["1", "0", "0", "0", "0"]),
        (20, ["0", "0", "0", "0", "0"]),
        (30, ["-1", "0", "0", "0", "0"]),
        (40, ["NaN", "10", "10", "10", "10"]),
    ]
    malformed = [
        "invalid,1,2,3,4,5",
        ",1,2,3,4,5",
        "12x,1,2,3,4,5",
    ]
    run_generated_case(records, malformed)


def test_dynamic_non_hardcoded_dataset():
    rng = secrets.SystemRandom()
    ids = rng.sample(range(-1000000, 1000001), 31)
    records = []
    for row_index, user_id in enumerate(ids):
        features = []
        for column in range(5):
            if (row_index * 5 + column) % 13 == 0:
                features.append("NaN")
            else:
                value = rng.randint(-500, 500) / 10.0
                features.append(f"{value:.1f}")
        records.append((user_id, features))

    malformed = [
        "invalid_id,0,0,0,0,0",
        ",9,8,7,6,5",
        "+-4,1,1,1,1,1",
    ]
    run_generated_case(records, malformed)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
