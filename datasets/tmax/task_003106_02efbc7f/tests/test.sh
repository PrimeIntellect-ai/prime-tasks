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
from collections import defaultdict

import pytest

C_PATH = "/home/user/find_pattern.c"
CSV_PATH = "/home/user/kg_edges.csv"
JSON_PATH = "/home/user/output.json"
BINARY_PATH = "/tmp/find_pattern_submission"


def compute_expected_results(csv_path):
    wrote = defaultdict(set)
    affiliated = defaultdict(set)

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) != 3:
                continue
            sub, rel, obj = row
            if rel == "WROTE":
                wrote[obj].add(sub)
            elif rel == "AFFILIATED_WITH":
                affiliated[obj].add(sub)

    author_inst = {}
    for inst, authors in affiliated.items():
        for author in authors:
            author_inst[author] = inst

    results = []
    for paper, authors in wrote.items():
        authors_list = sorted(authors)
        for i in range(len(authors_list)):
            for j in range(i + 1, len(authors_list)):
                a1 = authors_list[i]
                a2 = authors_list[j]
                if (a1 in author_inst and a2 in author_inst and
                        author_inst[a1] == author_inst[a2]):
                    results.append({
                        "A1": a1,
                        "A2": a2,
                        "P": paper,
                        "I": author_inst[a1],
                    })

    results.sort(key=lambda x: (x["P"], x["I"], x["A1"], x["A2"]))
    return results[:3]


def compile_program():
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", C_PATH, "-o", BINARY_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, "C program failed to compile:\n" + result.stderr
    assert os.path.isfile(BINARY_PATH), "Compilation did not produce an executable."


def run_and_validate():
    expected_data = compute_expected_results(CSV_PATH)

    if os.path.lexists(JSON_PATH):
        os.remove(JSON_PATH)

    result = subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Compiled C program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_PATH), (
        f"Output file {JSON_PATH} is missing. Did the C program run and generate it?"
    )

    with open(JSON_PATH, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON: {exc}")

    assert isinstance(actual_data, list), "Output JSON must be an array of objects."
    assert len(actual_data) == len(expected_data), (
        f"Expected {len(expected_data)} results, got {len(actual_data)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert set(actual.keys()) == {"A1", "A2", "P", "I"}, (
            f"Item at index {i} must have exactly the keys A1, A2, P, and I."
        )
        for key in ["A1", "A2", "P", "I"]:
            assert key in actual, f"Item at index {i} is missing key '{key}'."
            assert actual[key] == expected[key], (
                f"Mismatch at index {i} for key '{key}': "
                f"expected '{expected[key]}', got '{actual[key]}'."
            )


def make_generated_dataset():
    token = secrets.token_hex(4)
    def n(value):
        return f"{value}_{token}"

    rows = [
        [n("AuthorD"), "WROTE", n("PaperA")],
        [n("AuthorE"), "WROTE", n("PaperA")],
        [n("AuthorD"), "AFFILIATED_WITH", n("InstB")],
        [n("AuthorE"), "AFFILIATED_WITH", n("InstB")],
        [n("AuthorA"), "WROTE", n("PaperB")],
        [n("AuthorB"), "WROTE", n("PaperB")],
        [n("AuthorC"), "WROTE", n("PaperB")],
        [n("AuthorA"), "AFFILIATED_WITH", n("InstA")],
        [n("AuthorB"), "AFFILIATED_WITH", n("InstA")],
        [n("AuthorC"), "AFFILIATED_WITH", n("InstA")],
        # Same institution but different papers: these must not form a match.
        [n("CrossOne"), "WROTE", n("PaperC")],
        [n("CrossTwo"), "WROTE", n("PaperD")],
        [n("CrossOne"), "AFFILIATED_WITH", n("InstCross")],
        [n("CrossTwo"), "AFFILIATED_WITH", n("InstCross")],
        # Same paper but different institutions: this also must not match.
        [n("SplitOne"), "WROTE", n("PaperE")],
        [n("SplitTwo"), "WROTE", n("PaperE")],
        [n("SplitOne"), "AFFILIATED_WITH", n("InstLeft")],
        [n("SplitTwo"), "AFFILIATED_WITH", n("InstRight")],
    ]
    random.SystemRandom().shuffle(rows)
    return rows


def test_c_file_exists():
    assert os.path.isfile(C_PATH), f"Source file {C_PATH} is missing."


def test_compiled_program_generates_correct_output():
    assert os.path.isfile(CSV_PATH), f"Input file {CSV_PATH} is missing."
    assert os.path.isfile(C_PATH), f"Source file {C_PATH} is missing."
    compile_program()

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    try:
        # Preserve the original exact-result check.
        run_and_validate()

        # Exercise the compiled artifact on unpredictable input so a prewritten
        # output file or hard-coded answer cannot pass.
        with open(CSV_PATH, "w", newline="") as f:
            csv.writer(f, lineterminator="\n").writerows(make_generated_dataset())
        run_and_validate()
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)

    # Leave output.json generated by the submitted program for the real input.
    run_and_validate()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
