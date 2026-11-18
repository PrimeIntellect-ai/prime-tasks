#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import itertools
import json
import os
import re
import subprocess
import uuid

import pytest

SCRIPT = "/home/user/process_graph.sh"
OUTPUT = "/home/user/circular_citations.jsonl"
AUTHORS = "/home/user/authors.jsonl"
PAPERS = "/home/user/papers.csv"
CITATIONS = "/home/user/citations.txt"


@pytest.fixture(scope="module", autouse=True)
def execute_script_on_original_inputs():
    assert os.path.isfile(SCRIPT), f"Script missing: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script is not executable: {SCRIPT}"
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run([SCRIPT], cwd="/home/user", text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=20)
    assert result.returncode == 0, (
        f"Script failed on the original inputs with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_jsonl(path):
    records = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON line in output: {line}")
    return records


def test_script_exists_and_executable():
    script_path = "/home/user/process_graph.sh"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"
    with open(script_path, "r", encoding="utf-8", errors="replace") as f:
        first_line = f.readline().strip()
    assert re.match(r"^#!(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)(?:\s|$)", first_line), \
        "process_graph.sh must be a Bash script"


def test_output_file_exists():
    output_path = "/home/user/circular_citations.jsonl"
    assert os.path.isfile(output_path), f"Output file missing: {output_path}"


def test_output_file_content():
    output_path = "/home/user/circular_citations.jsonl"
    assert os.path.isfile(output_path), f"Output file missing: {output_path}"

    expected_data = [
        {"cycle_id": "P1-P2-P3", "authors": ["Alice Adams", "Bob Baker", "Charlie Clark"]},
        {"cycle_id": "P4-P5-P6", "authors": ["Diana Doe", "Evan Evans", "Fiona Fox"]}
    ]

    actual_data = read_jsonl(output_path)
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} cycles, found {len(actual_data)}"

    actual_data_sorted = sorted(actual_data, key=lambda x: x.get("cycle_id", ""))
    expected_data_sorted = sorted(expected_data, key=lambda x: x["cycle_id"])

    for actual, expected in zip(actual_data_sorted, expected_data_sorted):
        assert "cycle_id" in actual, "Missing 'cycle_id' in JSON object"
        assert "authors" in actual, "Missing 'authors' in JSON object"
        assert actual["cycle_id"] == expected["cycle_id"], \
            f"Expected cycle_id {expected['cycle_id']}, got {actual['cycle_id']}"
        assert isinstance(actual["authors"], list), "'authors' must be a list"
        assert actual["authors"] == sorted(actual["authors"]), \
            f"Authors list is not sorted alphabetically: {actual['authors']}"
        assert actual["authors"] == expected["authors"], \
            f"Expected authors {expected['authors']}, got {actual['authors']}"


def test_script_processes_altered_inputs():
    original_files = {}
    for path in (AUTHORS, PAPERS, CITATIONS, OUTPUT):
        original_files[path] = open(path, "rb").read() if os.path.exists(path) else None

    token = uuid.uuid4().hex[:10]
    paper_ids = [f"T{token}{letter}" for letter in "ABCDEFGH"]
    author_ids = [f"R{token}{i}" for i in range(8)]
    names = [
        f"Zulu {token}", f"Alpha {token}", f"Mike {token}",
        f"Echo {token}", f"Bravo {token}", f"Yankee {token}",
        f"Unused One {token}", f"Unused Two {token}"
    ]
    edges = {
        (paper_ids[0], paper_ids[2]),
        (paper_ids[2], paper_ids[1]),
        (paper_ids[1], paper_ids[0]),
        (paper_ids[3], paper_ids[5]),
        (paper_ids[5], paper_ids[4]),
        (paper_ids[4], paper_ids[3]),
        (paper_ids[0], paper_ids[3]),
        (paper_ids[1], paper_ids[4]),
        (paper_ids[6], paper_ids[7]),
    }

    paper_to_name = dict(zip(paper_ids, names))
    expected = []
    for triple in itertools.combinations(sorted(paper_ids), 3):
        a, b, c = triple
        forward = (a, b) in edges and (b, c) in edges and (c, a) in edges
        reverse = (a, c) in edges and (c, b) in edges and (b, a) in edges
        if forward or reverse:
            expected.append({
                "cycle_id": "-".join(triple),
                "authors": sorted(paper_to_name[p] for p in triple),
            })
    expected.sort(key=lambda record: record["cycle_id"])

    try:
        with open(AUTHORS, "w", encoding="utf-8") as f:
            for author_id, name in zip(author_ids, names):
                f.write(json.dumps({"author_id": author_id, "name": name}) + "\n")

        with open(PAPERS, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["paper_id", "title", "author_id"])
            for i, (paper_id, author_id) in enumerate(zip(paper_ids, author_ids), 1):
                writer.writerow([paper_id, f"Altered Title {i}", author_id])

        with open(CITATIONS, "w", encoding="utf-8") as f:
            for source, target in sorted(edges):
                f.write(f"{source} -> {target}\n")

        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        result = subprocess.run([SCRIPT], cwd="/home/user", text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=20)
        assert result.returncode == 0, (
            f"Script failed on altered inputs with exit code {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(OUTPUT), "Script did not create circular_citations.jsonl"

        actual = read_jsonl(OUTPUT)
        assert actual == expected, f"Expected derived cycles {expected}, got {actual}"
        assert [record["cycle_id"] for record in actual] == sorted(record["cycle_id"] for record in actual), \
            "JSONL records are not sorted by cycle_id"
        for record in actual:
            assert set(record.keys()) == {"cycle_id", "authors"}, \
                f"Output object does not match the required schema: {record}"
            assert record["authors"] == sorted(record["authors"]), \
                f"Authors are not sorted alphabetically: {record['authors']}"
    finally:
        for path, contents in original_files.items():
            if contents is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(contents)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
