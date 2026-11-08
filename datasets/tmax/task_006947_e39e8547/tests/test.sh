#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import uuid

SCRIPT_FILE = "/home/user/project_graph.sh"
INPUT_FILE = "/home/user/papers.jsonl"
OUTPUT_FILE = "/home/user/coauthors.csv"

ORIGINAL_EXPECTED_LINES = [
    "source,target",
    "Alice,Bob",
    "Alice,Charlie",
    "Alice,Dave",
    "Bob,Charlie",
    "Charlie,Eve",
    "Dave,Frank",
]


def run_script():
    result = subprocess.run(
        ["bash", SCRIPT_FILE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_FILE} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def read_nonempty_lines():
    assert os.path.isfile(OUTPUT_FILE), f"Expected output file {OUTPUT_FILE} does not exist."
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def derive_expected(records):
    edges = set()
    for record in records:
        if record["year"] < 2021:
            continue
        authors = record["authors"]
        for i in range(len(authors)):
            for j in range(i + 1, len(authors)):
                if authors[i] == authors[j]:
                    continue
                source, target = sorted((authors[i], authors[j]))
                edges.add((source, target))
    return ["source,target"] + [f"{source},{target}" for source, target in sorted(edges)]


def test_script_exists():
    assert os.path.isfile(SCRIPT_FILE), f"The script {SCRIPT_FILE} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT_FILE).st_mode), f"{SCRIPT_FILE} is not a regular file."
    syntax = subprocess.run(
        ["bash", "-n", SCRIPT_FILE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert syntax.returncode == 0, f"{SCRIPT_FILE} is not valid Bash: {syntax.stderr}"


def test_coauthors_csv_content():
    run_script()
    actual_lines = read_nonempty_lines()
    assert actual_lines == ORIGINAL_EXPECTED_LINES, (
        f"Content of {OUTPUT_FILE} does not match expected output.\n"
        f"Expected:\n{chr(10).join(ORIGINAL_EXPECTED_LINES)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_script_processes_changed_input_and_restores_original_output():
    token = uuid.uuid4().hex[:10]
    a = f"Alpha_{token}"
    b = f"Bravo_{token}"
    c = f"Charlie_{token}"
    d = f"Delta_{token}"
    e = f"Echo_{token}"
    old = f"Old_{token}"

    records = [
        {"paper_id": "hidden1", "year": 2021, "authors": [c, a, b], "references": []},
        {"paper_id": "hidden2", "year": 2020, "authors": [a, old], "references": []},
        {"paper_id": "hidden3", "year": 2022, "authors": [d, a], "references": ["hidden1"]},
        {"paper_id": "hidden4", "year": 2023, "authors": [e, d], "references": []},
        {"paper_id": "hidden5", "year": 2021, "authors": [b, e], "references": []},
        {"paper_id": "hidden6", "year": 2024, "authors": [a, d], "references": []},
        {"paper_id": "hidden7", "year": 2021, "authors": [old], "references": []},
    ]
    expected = derive_expected(records)

    with open(INPUT_FILE, "rb") as f:
        original_input = f.read()

    try:
        with open(INPUT_FILE, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        run_script()
        actual = read_nonempty_lines()
        assert actual == expected, (
            "The script did not derive the graph from the changed input.\n"
            f"Expected:\n{chr(10).join(expected)}\n\n"
            f"Actual:\n{chr(10).join(actual)}"
        )
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)
        run_script()

    restored_lines = read_nonempty_lines()
    assert restored_lines == ORIGINAL_EXPECTED_LINES, (
        "The script did not regenerate the required final CSV after restoring the original input."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
