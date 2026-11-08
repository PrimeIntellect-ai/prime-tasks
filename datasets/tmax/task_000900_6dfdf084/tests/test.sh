#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess

import pytest
import requests

URL = "http://127.0.0.1:8080/api/graph/coauthors"
DATASET = "/home/user/data/papers.jsonl"
WHITEBOARD = "/app/whiteboard.png"


def get_response():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(
            f"Failed to connect to the server at {URL}. Ensure the server is running "
            f"and listening on port 8080. Error: {e}"
        )

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response body: {response.text}"
    )

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")

    assert isinstance(data, list), f"Expected response to be a JSON array, got {type(data).__name__}"
    assert all(isinstance(item, str) for item in data), "Every co-author ID must be a JSON string"
    assert len(data) == len(set(data)), "Response must contain only unique co-author IDs"
    return data


def primary_author_from_whiteboard():
    text = subprocess.check_output(
        ["tesseract", WHITEBOARD, "stdout"], stderr=subprocess.DEVNULL, text=True
    )
    match = re.search(r"A-\d+", text)
    assert match, f"Could not derive a Primary Author ID from OCR output: {text!r}"
    return match.group(0)


def expected_from_dataset(primary_author):
    result = set()
    with open(DATASET, "r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            document = json.loads(line)
            authors = document["authors"]
            if primary_author in authors:
                result.update(author for author in authors if author != primary_author)
    return result


def test_coauthors_endpoint_executes_pipeline():
    # Preserve the original endpoint and fixed-result assertion.
    data = get_response()
    expected_coauthors = {"A-311", "A-412", "A-500", "A-701"}
    actual_coauthors = set(data)
    assert actual_coauthors == expected_coauthors, (
        f"Expected co-authors {expected_coauthors}, but got {actual_coauthors}"
    )

    primary_author = primary_author_from_whiteboard()
    with open(DATASET, "rb") as handle:
        original_dataset = handle.read()

    # Replace the input with an unpredictable graph so a fixed response cannot pass.
    generated = set()
    while len(generated) < 4:
        generated.add(f"A-DYNAMIC-{secrets.token_hex(8)}")
    coauthor_one, coauthor_two, unrelated_one, unrelated_two = generated

    documents = [
        {"paper_id": "DYN-1", "authors": [primary_author, coauthor_one, coauthor_one]},
        {"paper_id": "DYN-2", "authors": [coauthor_two, primary_author, primary_author]},
        {"paper_id": "DYN-3", "authors": [unrelated_one, unrelated_two]},
        {"paper_id": "DYN-4", "authors": [primary_author]},
    ]
    replacement = "".join(json.dumps(doc) + "\n" for doc in documents).encode("utf-8")
    temporary_path = DATASET + ".verifier-tmp"

    try:
        with open(temporary_path, "wb") as handle:
            handle.write(replacement)
        os.chmod(temporary_path, 0o666)
        os.replace(temporary_path, DATASET)

        expected_dynamic = expected_from_dataset(primary_author)
        dynamic_data = get_response()
        assert set(dynamic_data) == expected_dynamic, (
            f"After changing the publications graph, expected co-authors "
            f"{expected_dynamic}, but got {set(dynamic_data)}"
        )
    finally:
        with open(temporary_path, "wb") as handle:
            handle.write(original_dataset)
        os.chmod(temporary_path, 0o666)
        os.replace(temporary_path, DATASET)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
