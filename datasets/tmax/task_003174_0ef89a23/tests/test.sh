#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/classifier.py"
EMPLOYEES_PATH = "/app/employees.csv"


def invoke_classifier(input_dir):
    with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
        output_csv = tmp.name
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, input_dir, output_csv],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Script failed: {result.stderr}"
        assert os.path.exists(output_csv), "Output CSV was not created."

        with open(output_csv, "r", newline="") as f:
            raw_rows = list(csv.reader(f))

        assert raw_rows, "Output CSV is empty."
        assert raw_rows[0] == ["filename", "status"], \
            "Output CSV must contain exactly the columns 'filename' and 'status', in that order."
        assert all(len(row) == 2 for row in raw_rows), \
            "Every output CSV row must contain exactly two columns."

        data_rows = raw_rows[1:]
        assert all(row[1] in ("clean", "evil") for row in data_rows), \
            "Every status must be either 'clean' or 'evil'."
        filenames = [row[0] for row in data_rows]
        assert len(filenames) == len(set(filenames)), \
            "Output CSV must not contain duplicate filename rows."
        return dict(data_rows), data_rows
    finally:
        if os.path.exists(output_csv):
            os.remove(output_csv)


def test_classifier_exists():
    assert os.path.exists(SCRIPT_PATH), "classifier.py not found at /home/user/classifier.py"
    assert os.path.isfile(SCRIPT_PATH), "classifier.py must be a regular file"


def test_classifier_clean_corpus():
    input_dir = "/app/corpus/clean"
    results, rows = invoke_classifier(input_dir)

    # Preserve the original corpus assertions.
    expected_files = [f for f in os.listdir(input_dir) if f.endswith(".json")]
    failed_files = []
    for filename in expected_files:
        if filename not in results:
            failed_files.append(f"{filename} (missing)")
        elif results[filename] != "clean":
            failed_files.append(f"{filename} (status: {results[filename]})")
    assert not failed_files, \
        f"{len(failed_files)} of {len(expected_files)} clean files modified/flagged incorrectly: {', '.join(failed_files)}"

    assert len(rows) == len(expected_files), "Output must have exactly one row per input JSON file."
    assert set(results) == set(expected_files), "Output contains missing or extra filenames."


def test_classifier_evil_corpus():
    input_dir = "/app/corpus/evil"
    results, rows = invoke_classifier(input_dir)

    # Preserve the original corpus assertions.
    expected_files = [f for f in os.listdir(input_dir) if f.endswith(".json")]
    failed_files = []
    for filename in expected_files:
        if filename not in results:
            failed_files.append(f"{filename} (missing)")
        elif results[filename] != "evil":
            failed_files.append(f"{filename} (status: {results[filename]})")
    assert not failed_files, \
        f"{len(failed_files)} of {len(expected_files)} evil files bypassed/flagged incorrectly: {', '.join(failed_files)}"

    assert len(rows) == len(expected_files), "Output must have exactly one row per input JSON file."
    assert set(results) == set(expected_files), "Output contains missing or extra filenames."


def test_mixed_randomized_corpus_and_dynamic_hierarchy():
    with open(EMPLOYEES_PATH, "rb") as f:
        original_employees = f.read()

    existing_ids = set()
    with open(EMPLOYEES_PATH, newline="") as f:
        for row in csv.DictReader(f):
            existing_ids.add(int(row["emp_id"]))

    generated = set()
    while len(generated) < 4:
        candidate = secrets.randbelow(800000000) + 100000000
        if candidate not in existing_ids:
            generated.add(candidate)
    direct_id, middle_id, deep_id, unrelated_id = list(generated)

    try:
        with open(EMPLOYEES_PATH, "a", newline="") as f:
            writer = csv.writer(f)
            writer.writerow([direct_id, "Generated Direct", 8492, "Sales"])
            writer.writerow([middle_id, "Generated Middle", direct_id, "Sales"])
            writer.writerow([deep_id, "Generated Deep", middle_id, "Sales"])
            writer.writerow([unrelated_id, "Generated Safe", "", "IT"])

        cases = [
            ({"author_id": 8492, "query_payload": {"$eq": 1}}, "evil"),
            ({"author_id": direct_id, "query_payload": {"normal": True}}, "evil"),
            ({"author_id": deep_id, "query_payload": {"nested": {"safe": 1}}}, "evil"),
            ({"author_id": 2003, "query_payload": {"$in": [1, 2]}}, "evil"),
            ({"author_id": 9000, "query_payload": {"nested": {"$where": "x"}}}, "evil"),
            ({"author_id": unrelated_id, "query_payload": {"items": [{"$regex": ".*"}]}}, "evil"),
            ({"author_id": 9000, "query_payload": {"$eq": "$where"}}, "clean"),
            ({"author_id": unrelated_id, "query_payload": {"message": "contains $regex as a value"}}, "clean"),
            ({"author_id": 9001, "query_payload": {"nested": {"$in": ["a"]}}}, "clean"),
            ({"author_id": unrelated_id, "query_payload": {"safe": True}, "$where": "outside payload"}, "clean"),
        ]
        random.SystemRandom().shuffle(cases)

        with tempfile.TemporaryDirectory() as input_dir:
            expected = {}
            for document, status in cases:
                filename = f"{secrets.token_hex(12)}.json"
                expected[filename] = status
                with open(os.path.join(input_dir, filename), "w") as f:
                    json.dump(document, f)

            # Non-JSON files must not produce output rows.
            with open(os.path.join(input_dir, f"{secrets.token_hex(8)}.txt"), "w") as f:
                f.write("ignore me")

            results, rows = invoke_classifier(input_dir)
            assert len(rows) == len(expected), "Output must have exactly one row per input JSON file."
            assert set(results) == set(expected), "Output contains missing or extra filenames."
            assert results == expected, "Classifier produced incorrect results on the mixed randomized corpus."
    finally:
        with open(EMPLOYEES_PATH, "wb") as f:
            f.write(original_employees)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
