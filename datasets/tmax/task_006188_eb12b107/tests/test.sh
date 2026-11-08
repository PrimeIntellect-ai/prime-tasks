#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess

import pytest

ANALYZE_SCRIPT = "/home/user/analyze.sh"
TOP_PAPERS_FILE = "/home/user/top_papers.json"
DATASET_DIR = "/home/user/dataset"


def test_analyze_script_exists():
    assert os.path.isfile(ANALYZE_SCRIPT), f"The script '{ANALYZE_SCRIPT}' does not exist."


def test_top_papers_file_exists():
    assert os.path.isfile(TOP_PAPERS_FILE), f"The output file '{TOP_PAPERS_FILE}' was not generated."


def test_top_papers_content():
    assert os.path.isfile(TOP_PAPERS_FILE), f"The output file '{TOP_PAPERS_FILE}' is missing."

    try:
        with open(TOP_PAPERS_FILE, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file '{TOP_PAPERS_FILE}' does not contain valid JSON.")

    expected_data = [
        {
            "id": "P1",
            "citing_institutions_count": 3
        },
        {
            "id": "P2",
            "citing_institutions_count": 2
        },
        {
            "id": "P3",
            "citing_institutions_count": 2
        }
    ]

    assert isinstance(data, list), f"The root of '{TOP_PAPERS_FILE}' must be a JSON array."
    assert len(data) == 3, f"Expected exactly 3 results in '{TOP_PAPERS_FILE}', but found {len(data)}."

    for i, expected_item in enumerate(expected_data):
        assert data[i] == expected_item, (
            f"Mismatch at index {i} in '{TOP_PAPERS_FILE}'. "
            f"Expected: {expected_item}, Got: {data[i]}"
        )


def expected_for(documents):
    citing_institutions = {doc["id"]: set() for doc in documents}
    for citing_doc in documents:
        for cited_id in citing_doc["citations"]:
            if cited_id in citing_institutions:
                citing_institutions[cited_id].add(citing_doc["institution"])

    results = [
        {
            "id": paper_id,
            "citing_institutions_count": len(institutions),
        }
        for paper_id, institutions in citing_institutions.items()
    ]
    results.sort(key=lambda item: (-item["citing_institutions_count"], item["id"]))
    return results[:3]


def read_dataset():
    documents = []
    for name in sorted(os.listdir(DATASET_DIR)):
        if name.endswith(".json"):
            with open(os.path.join(DATASET_DIR, name), "r") as f:
                documents.append(json.load(f))
    return documents


def run_and_check(documents):
    expected = expected_for(documents)
    if os.path.lexists(TOP_PAPERS_FILE):
        os.unlink(TOP_PAPERS_FILE)

    completed = subprocess.run(
        ["/bin/bash", ANALYZE_SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"Executing '{ANALYZE_SCRIPT}' failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(TOP_PAPERS_FILE), (
        f"Executing '{ANALYZE_SCRIPT}' did not generate '{TOP_PAPERS_FILE}'."
    )

    try:
        with open(TOP_PAPERS_FILE, "r") as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The generated output is not valid JSON: {exc}")

    assert isinstance(actual, list), "The generated output must be a JSON array."
    assert len(actual) == 3, "The generated output must contain exactly the top 3 papers."
    assert actual == expected, f"Expected dynamically computed result {expected}, got {actual}."


def test_script_executes_and_computes_pipeline():
    # First require the submitted script to regenerate the result from the original dataset.
    original_documents = read_dataset()
    run_and_check(original_documents)

    # Then replace the dataset with an unpredictable valid citation graph so a hardcoded
    # script cannot pass. This graph also checks duplicate citations, repeated institutions,
    # distinct-institution aggregation, tie sorting, and inclusion of all dataset papers.
    token = secrets.token_hex(8)
    ids = [f"P_{secrets.token_hex(6)}_{token}" for _ in range(9)]
    inst = [f"Institution_{secrets.token_hex(5)}" for _ in range(5)]
    documents = [
        {"id": ids[0], "title": "Doc 0", "institution": inst[0], "citations": [ids[3], ids[3], ids[4]]},
        {"id": ids[1], "title": "Doc 1", "institution": inst[0], "citations": [ids[3], ids[5]]},
        {"id": ids[2], "title": "Doc 2", "institution": inst[1], "citations": [ids[3], ids[4]]},
        {"id": ids[3], "title": "Doc 3", "institution": inst[2], "citations": [ids[4]]},
        {"id": ids[4], "title": "Doc 4", "institution": inst[3], "citations": [ids[5]]},
        {"id": ids[5], "title": "Doc 5", "institution": inst[1], "citations": [ids[0]]},
        {"id": ids[6], "title": "Doc 6", "institution": inst[4], "citations": []},
        {"id": ids[7], "title": "Doc 7", "institution": inst[2], "citations": [ids[5]]},
        {"id": ids[8], "title": "Doc 8", "institution": inst[3], "citations": [ids[6]]},
    ]

    shutil.rmtree(DATASET_DIR)
    os.makedirs(DATASET_DIR)
    for index, document in enumerate(documents):
        with open(os.path.join(DATASET_DIR, f"document_{index}.json"), "w") as f:
            json.dump(document, f)

    run_and_check(documents)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
