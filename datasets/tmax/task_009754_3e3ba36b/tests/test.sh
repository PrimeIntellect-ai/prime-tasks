#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import stat
import subprocess

SOURCE = "/home/user/etl.go"
INPUT = "/home/user/data/feedback.csv"
OUTPUT_DIR = "/home/user/output"
EMBEDDINGS = os.path.join(OUTPUT_DIR, "embeddings.jsonl")
METRICS = os.path.join(OUTPUT_DIR, "run_metrics.txt")
BINARY = "/tmp/verified_etl"
MARKER = "Prior metrics entry"


def fnv1a32(token):
    value = 2166136261
    for byte in token.encode("utf-8"):
        value ^= byte
        value = (value * 16777619) & 0xffffffff
    return value


def expected_vector(text):
    cleaned = text.lower()
    for punctuation in ".,!?":
        cleaned = cleaned.replace(punctuation, "")
    vector = [0] * 10
    for token in cleaned.split():
        vector[fnv1a32(token) % 10] += 1
    return vector


def write_fixture(rows):
    os.makedirs(os.path.dirname(INPUT), exist_ok=True)
    with open(INPUT, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["id", "timestamp", "text", "rating"])
        writer.writerows(rows)


def reset_outputs():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for path in (EMBEDDINGS, METRICS):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        elif os.path.lexists(path):
            os.unlink(path)
    with open(METRICS, "w", encoding="utf-8") as handle:
        handle.write(MARKER + "\n")


def execute_etl():
    result = subprocess.run(
        [BINARY], cwd="/home/user", text=True, capture_output=True, timeout=15
    )
    assert result.returncode == 0, (
        f"Compiled ETL program exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_embeddings(expected_count):
    assert os.path.exists(EMBEDDINGS), (
        f"File {EMBEDDINGS} does not exist. The Go program must create it."
    )
    assert os.path.isfile(EMBEDDINGS), f"{EMBEDDINGS} is not a regular file."
    with open(EMBEDDINGS, "r", encoding="utf-8") as handle:
        lines = [line.strip() for line in handle.readlines() if line.strip()]
    assert len(lines) == expected_count, (
        f"Expected {expected_count} lines in {EMBEDDINGS}, but found {len(lines)}."
    )
    objects = []
    for i, line in enumerate(lines):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Line {i + 1} in {EMBEDDINGS} is not valid JSON: {exc}")
        assert isinstance(obj, dict), f"Line {i + 1} must be a JSON object."
        assert "id" in obj, f"Missing 'id' key in line {i + 1} of {EMBEDDINGS}."
        assert "vector" in obj, f"Missing 'vector' key in line {i + 1} of {EMBEDDINGS}."
        assert set(obj) == {"id", "vector"}, (
            f"Line {i + 1} must contain exactly the 'id' and 'vector' keys."
        )
        assert isinstance(obj["id"], str), f"The id in line {i + 1} must be a string."
        assert isinstance(obj["vector"], list), f"The vector in line {i + 1} must be an array."
        assert len(obj["vector"]) == 10, f"The vector in line {i + 1} must have length 10."
        assert all(type(value) is int for value in obj["vector"]), (
            f"Every vector value in line {i + 1} must be an integer."
        )
        objects.append(obj)
    return objects


def check_metrics(record_count):
    assert os.path.exists(METRICS), (
        f"File {METRICS} does not exist. The Go program must create it."
    )
    assert os.path.isfile(METRICS), f"{METRICS} is not a regular file."
    with open(METRICS, "r", encoding="utf-8") as handle:
        content = handle.read().strip()
    expected_content = f"Run completed. Total records processed: {record_count}"
    assert expected_content in content, (
        f"Expected '{expected_content}' to be in {METRICS}, but found:\n{content}"
    )
    assert content.splitlines() == [MARKER, expected_content], (
        "The program must append exactly one correctly formatted summary line without "
        "overwriting existing metrics."
    )


def test_original_fixture():
    rows = [
        ["1", "2023-10-01", "Great product, but slow shipping.", "4"],
        ["2", "2023-10-02", "Terrible! I absolutely hate it.", "1"],
        ["3", "2023-10-03", "Very good! I will buy again.", "5"],
    ]
    write_fixture(rows)
    reset_outputs()
    execute_etl()
    objects = read_embeddings(3)

    expected_vectors = {
        "1": [0, 1, 0, 0, 1, 1, 1, 1, 0, 0],
        "2": [2, 0, 0, 0, 1, 0, 1, 1, 0, 0],
        "3": [1, 0, 0, 0, 0, 1, 1, 1, 0, 2],
    }
    expected_order = ["1", "2", "3"]
    assert [obj["id"] for obj in objects] == expected_order, (
        "Embedding IDs must be unique and in the same order as the input rows."
    )
    for obj in objects:
        row_id = obj["id"]
        assert row_id in expected_vectors, f"Unexpected id '{row_id}' found in {EMBEDDINGS}."
        expected = expected_vectors[row_id]
        assert obj["vector"] == expected, (
            f"Incorrect vector for id '{row_id}'. Expected {expected}, got {obj['vector']}."
        )
    check_metrics(3)


def test_runtime_generated_fixture():
    nonce = secrets.token_hex(6)
    rows = [
        [f"customer-{nonce}-c", "2026-01-03", f"LOUD{nonce}, quiet! LOUD{nonce}? end.", "4"],
        [f"customer-{nonce}-a", "2026-01-01", f"Dots... Commas,,, Bang!!! Query??? {nonce}", "2"],
        [f"customer-{nonce}-d", "2026-01-04", f"MiXeD{nonce}\tCase, two  spaces", "5"],
        [f"customer-{nonce}-b", "2026-01-02", f"repeat repeat REPEAT, unique{nonce}", "1"],
    ]
    write_fixture(rows)
    reset_outputs()
    execute_etl()
    objects = read_embeddings(len(rows))

    expected_ids = [row[0] for row in rows]
    assert [obj["id"] for obj in objects] == expected_ids, (
        "Embedding IDs must be unique and in exactly the input CSV order."
    )
    for obj, row in zip(objects, rows):
        expected = expected_vector(row[2])
        assert obj["vector"] == expected, (
            f"Incorrect runtime-derived vector for id '{row[0]}'. "
            f"Expected {expected}, got {obj['vector']}."
        )
    check_metrics(len(rows))


def main():
    assert os.path.lexists(SOURCE), f"Required Go source file {SOURCE} does not exist."
    assert not os.path.islink(SOURCE), f"{SOURCE} must be a regular Go source file, not a symlink."
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"{SOURCE} is not a regular file."
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty."

    if os.path.lexists(BINARY):
        os.unlink(BINARY)
    build = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=45,
    )
    assert build.returncode == 0, (
        f"Failed to compile {SOURCE} as a Go program.\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    test_original_fixture()
    test_runtime_generated_fixture()


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
