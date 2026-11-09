#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import itertools
import json
import os
import random
import secrets
import subprocess

import pytest

SCRIPT = "/home/user/find_deadlocks.py"
DERIVATIONS = "/home/user/derivations.tsv"
METADATA = "/home/user/metadata.tsv"
OUTPUT = "/home/user/deadlocks.json"


def run_script():
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"find_deadlocks.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    assert os.path.isfile(OUTPUT), f"Path {OUTPUT} is not a file."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT} is not valid JSON.")


def derive_expected():
    with open(DERIVATIONS, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    edges = {
        (row["Source"], row["Target"])
        for row in rows
        if row["Relation"] == "DERIVED_FROM"
    }
    nodes = sorted({node for edge in edges for node in edge})

    with open(METADATA, newline="", encoding="utf-8") as f:
        metadata = {
            row["DatasetID"]: row["ResearcherName"]
            for row in csv.DictReader(f, delimiter="\t")
        }

    cycles = []
    for triple in itertools.combinations(nodes, 3):
        has_cycle = any(
            (order[0], order[1]) in edges
            and (order[1], order[2]) in edges
            and (order[2], order[0]) in edges
            for order in itertools.permutations(triple)
        )
        if has_cycle:
            cycles.append({
                "cycle_nodes": list(triple),
                "researchers": sorted({metadata[node] for node in triple}),
            })
    cycles.sort(key=lambda item: item["cycle_nodes"][0])
    return cycles


def write_hidden_fixture():
    token = secrets.token_hex(6)
    ids = {letter: f"H_{token}_{letter}" for letter in "ABCDEFGHIJKLMNOPQR"}
    researcher = {
        letter: f"Researcher_{secrets.token_hex(3)}"
        for letter in ids
    }
    # Exercise researcher de-duplication within a valid cycle.
    researcher["E"] = researcher["D"]

    derivations = [
        # Two valid directed 3-cycles.
        (ids["A"], ids["B"], "DERIVED_FROM"),
        (ids["B"], ids["C"], "DERIVED_FROM"),
        (ids["C"], ids["A"], "DERIVED_FROM"),
        (ids["D"], ids["F"], "DERIVED_FROM"),
        (ids["F"], ids["E"], "DERIVED_FROM"),
        (ids["E"], ids["D"], "DERIVED_FROM"),
        # A triangle whose closing edge has the wrong relation.
        (ids["G"], ids["H"], "DERIVED_FROM"),
        (ids["H"], ids["I"], "DERIVED_FROM"),
        (ids["I"], ids["G"], "CITES"),
        # Cycles of lengths two and four must not be reported.
        (ids["J"], ids["K"], "DERIVED_FROM"),
        (ids["K"], ids["J"], "DERIVED_FROM"),
        (ids["L"], ids["M"], "DERIVED_FROM"),
        (ids["M"], ids["N"], "DERIVED_FROM"),
        (ids["N"], ids["O"], "DERIVED_FROM"),
        (ids["O"], ids["L"], "DERIVED_FROM"),
        # An incomplete path and a self-loop.
        (ids["P"], ids["Q"], "DERIVED_FROM"),
        (ids["Q"], ids["R"], "DERIVED_FROM"),
        (ids["R"], ids["R"], "DERIVED_FROM"),
    ]
    metadata = [
        (dataset_id, researcher[letter], str(1980 + index))
        for index, (letter, dataset_id) in enumerate(ids.items())
    ]
    random.SystemRandom().shuffle(derivations)
    random.SystemRandom().shuffle(metadata)

    with open(DERIVATIONS, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t", lineterminator="\n")
        writer.writerow(["Source", "Target", "Relation"])
        writer.writerows(derivations)
    with open(METADATA, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t", lineterminator="\n")
        writer.writerow(["DatasetID", "ResearcherName", "CreationYear"])
        writer.writerows(metadata)


def assert_exact_format(data):
    assert isinstance(data, list), "The JSON root must be a list."
    for i, item in enumerate(data):
        assert isinstance(item, dict), f"Item at index {i} is not a JSON object (dictionary)."
        assert set(item) == {"cycle_nodes", "researchers"}, (
            f"Item at index {i} must have exactly 'cycle_nodes' and 'researchers' keys."
        )
        assert item["cycle_nodes"] == sorted(item["cycle_nodes"]), (
            f"cycle_nodes at index {i} is not lexicographically sorted."
        )
        assert len(item["cycle_nodes"]) == 3
        assert len(set(item["cycle_nodes"])) == 3
        assert item["researchers"] == sorted(set(item["researchers"])), (
            f"researchers at index {i} is not a sorted unique list."
        )
    assert data == sorted(data, key=lambda item: item["cycle_nodes"][0]), (
        "The JSON array is not sorted by the first cycle node."
    )


def test_deadlocks_json_exists_and_correct():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"Path {SCRIPT} is not a file."

    original_derivations = open(DERIVATIONS, "rb").read()
    original_metadata = open(METADATA, "rb").read()
    original_output = open(OUTPUT, "rb").read() if os.path.isfile(OUTPUT) else None

    try:
        data = run_script()
        expected = [
            {"cycle_nodes": ["DS1", "DS2", "DS3"], "researchers": ["Alice", "Bob"]},
            {"cycle_nodes": ["DS4", "DS5", "DS6"], "researchers": ["Charlie", "Dave", "Eve"]}
        ]

        assert isinstance(data, list), "The JSON root must be a list."
        assert len(data) == len(expected), f"Expected {len(expected)} cycles, found {len(data)}."

        for i, expected_obj in enumerate(expected):
            actual_obj = data[i]
            assert isinstance(actual_obj, dict), f"Item at index {i} is not a JSON object (dictionary)."
            assert "cycle_nodes" in actual_obj, f"Item at index {i} is missing 'cycle_nodes' key."
            assert "researchers" in actual_obj, f"Item at index {i} is missing 'researchers' key."
            assert actual_obj["cycle_nodes"] == expected_obj["cycle_nodes"], (
                f"Expected cycle_nodes {expected_obj['cycle_nodes']} at index {i}, "
                f"but got {actual_obj['cycle_nodes']}."
            )
            assert actual_obj["researchers"] == expected_obj["researchers"], (
                f"Expected researchers {expected_obj['researchers']} at index {i}, "
                f"but got {actual_obj['researchers']}."
            )

        assert_exact_format(data)

        write_hidden_fixture()
        hidden_expected = derive_expected()
        hidden_data = run_script()
        assert_exact_format(hidden_data)
        assert hidden_data == hidden_expected, (
            "Output for the hidden TSV fixture does not match the cycles and metadata "
            "derived from those input files."
        )
    finally:
        with open(DERIVATIONS, "wb") as f:
            f.write(original_derivations)
        with open(METADATA, "wb") as f:
            f.write(original_metadata)
        if original_output is None:
            if os.path.lexists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
