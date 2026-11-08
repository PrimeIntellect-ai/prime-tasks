#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tempfile

import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "find_pattern.go")
GO_MOD = os.path.join(HOME, "go.mod")
DATASET = os.path.join(HOME, "dataset", "graph.jsonl")
RESULTS = os.path.join(HOME, "results.json")

EXPECTED_ORIGINAL = [
    {
        "paper_a": "Graph AI",
        "paper_b": "Neural Nets",
        "researcher_a": "Alice",
        "researcher_b": "Bob"
    },
    {
        "paper_a": "Data Mining",
        "paper_b": "Graph AI",
        "researcher_a": "Alice",
        "researcher_b": "Alice"
    },
    {
        "paper_a": "Neural Nets",
        "paper_b": "Data Mining",
        "researcher_a": "Bob",
        "researcher_b": "Alice"
    },
    {
        "paper_a": "Neural Nets",
        "paper_b": "Data Mining",
        "researcher_a": "Bob",
        "researcher_b": "Charlie"
    },
    {
        "paper_a": "Data Mining",
        "paper_b": "Graph AI",
        "researcher_a": "Charlie",
        "researcher_b": "Alice"
    }
]


def derive_expected(records):
    researchers = {}
    papers = {}
    authored = []
    cites = []

    for record in records:
        if record.get("node_type") == "Researcher":
            researchers[record["node_id"]] = record["attributes"]["name"]
        elif record.get("node_type") == "Paper":
            papers[record["node_id"]] = record["attributes"]["title"]
        elif record.get("rel_type") == "AUTHORED":
            authored.append((record["source"], record["target"]))
        elif record.get("rel_type") == "CITES":
            cites.append((record["source"], record["target"]))

    authors_by_paper = {}
    for researcher_id, paper_id in authored:
        authors_by_paper.setdefault(paper_id, []).append(researcher_id)

    expected = []
    for paper_a_id, paper_b_id in cites:
        for researcher_a_id in authors_by_paper.get(paper_a_id, []):
            for researcher_b_id in authors_by_paper.get(paper_b_id, []):
                expected.append({
                    "researcher_a": researchers[researcher_a_id],
                    "researcher_b": researchers[researcher_b_id],
                    "paper_a": papers[paper_a_id],
                    "paper_b": papers[paper_b_id],
                })

    expected.sort(key=lambda item: (item["researcher_a"], item["researcher_b"]))
    return expected


def run_program(executable):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    completed = subprocess.run(
        [executable],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        "The compiled Go program failed.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS), "The output file /home/user/results.json does not exist."

    try:
        with open(RESULTS, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The output file /home/user/results.json is not valid JSON: {exc}")


def test_go_implementation_and_results():
    assert os.path.exists(SOURCE), "The required /home/user/find_pattern.go does not exist."
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), "/home/user/find_pattern.go must be a regular Go source file."
    assert os.path.isfile(GO_MOD), "The Go module was not initialized at /home/user/go.mod."

    with open(DATASET, "rb") as handle:
        original_dataset = handle.read()

    verified_original_results = None
    dynamic_records = [
        {"node_id": "person_d", "node_type": "Researcher", "attributes": {"name": "Delta"}},
        {"node_id": "person_e", "node_type": "Researcher", "attributes": {"name": "Echo"}},
        {"node_id": "person_b", "node_type": "Researcher", "attributes": {"name": "Bravo"}},
        {"node_id": "person_f", "node_type": "Researcher", "attributes": {"name": "Foxtrot"}},
        {"node_id": "paper_alpha", "node_type": "Paper", "attributes": {"title": "Alpha Study"}},
        {"node_id": "paper_beta", "node_type": "Paper", "attributes": {"title": "Beta Study"}},
        {"node_id": "paper_gamma", "node_type": "Paper", "attributes": {"title": "Gamma Study"}},
        {"node_id": "paper_delta", "node_type": "Paper", "attributes": {"title": "Delta Study"}},
        {"source": "person_d", "target": "paper_alpha", "rel_type": "AUTHORED"},
        {"source": "person_e", "target": "paper_beta", "rel_type": "AUTHORED"},
        {"source": "person_b", "target": "paper_gamma", "rel_type": "AUTHORED"},
        {"source": "person_f", "target": "paper_delta", "rel_type": "AUTHORED"},
        {"source": "paper_alpha", "target": "paper_beta", "rel_type": "CITES"},
        {"source": "paper_gamma", "target": "paper_delta", "rel_type": "CITES"},
        {"source": "paper_beta", "target": "paper_delta", "rel_type": "MENTIONS"}
    ]

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            executable = os.path.join(temp_dir, "find_pattern")
            build = subprocess.run(
                ["go", "build", "-o", executable, "find_pattern.go"],
                cwd=HOME,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=60,
            )
            assert build.returncode == 0, (
                "The required Go program does not compile.\n"
                f"stdout:\n{build.stdout}\n"
                f"stderr:\n{build.stderr}"
            )

            original_results = run_program(executable)
            assert isinstance(original_results, list), "The results must be a JSON array."
            assert len(original_results) == len(EXPECTED_ORIGINAL), (
                f"Expected {len(EXPECTED_ORIGINAL)} results, but got {len(original_results)}."
            )
            assert original_results == EXPECTED_ORIGINAL, (
                "The results do not match the expected output exactly or are not sorted correctly."
            )
            with open(RESULTS, "rb") as handle:
                verified_original_results = handle.read()

            with open(DATASET, "w", encoding="utf-8") as handle:
                for record in dynamic_records:
                    handle.write(json.dumps(record) + "\n")

            dynamic_results = run_program(executable)
            dynamic_expected = derive_expected(dynamic_records)
            assert dynamic_results == dynamic_expected, (
                "The Go program did not reconstruct and query the supplied graph dataset correctly."
            )
    finally:
        with open(DATASET, "wb") as handle:
            handle.write(original_dataset)
        if verified_original_results is not None:
            with open(RESULTS, "wb") as handle:
                handle.write(verified_original_results)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
