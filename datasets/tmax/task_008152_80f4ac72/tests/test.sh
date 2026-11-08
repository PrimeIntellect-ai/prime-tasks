#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from pathlib import Path

import pytest

SCRIPT_PATH = Path("/home/user/prepare_features.py")
JSON_PATH = Path("/home/user/features.json")
FASTA_PATH = Path("/home/user/data/sequences.fasta")
PDB_PATH = Path("/home/user/data/structure.pdb")


def run_script():
    result = subprocess.run(
        ["python3", str(SCRIPT_PATH)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"prepare_features.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission_on_original_inputs():
    assert SCRIPT_PATH.is_file(), f"The script {SCRIPT_PATH} is missing."
    if JSON_PATH.exists():
        JSON_PATH.unlink()
    run_script()
    yield


def test_prepare_features_script_exists():
    script_path = "/home/user/prepare_features.py"
    assert os.path.isfile(script_path), f"The script {script_path} is missing."


def test_features_json_exists():
    json_path = "/home/user/features.json"
    assert os.path.isfile(json_path), f"The output file {json_path} is missing."


def test_features_json_content():
    json_path = "/home/user/features.json"
    assert os.path.isfile(json_path), f"The output file {json_path} is missing."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    expected_data = {
        "A": {
            "ca_count": 2,
            "length_diff_from_mean": -1.0
        },
        "B": {
            "ca_count": 3,
            "length_diff_from_mean": 2.0
        }
    }

    assert data == expected_data, f"The contents of {json_path} do not match the expected output. Got: {data}"


def test_features_json_keys_sorted():
    json_path = "/home/user/features.json"
    assert os.path.isfile(json_path), f"The output file {json_path} is missing."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    keys = list(data.keys())
    assert keys == sorted(keys), "The keys in the output JSON file are not sorted alphabetically."


def pdb_text(atoms):
    lines = []
    for serial, (atom_name, chain, residue_number) in enumerate(atoms, 1):
        lines.append(
            f"ATOM  {serial:5d} {atom_name:>4s} ALA {chain:1s}{residue_number:4d}    "
            f"{10.0 + serial:8.3f}{12.0:8.3f}{14.0:8.3f}  1.00  0.00           C  "
        )
    return "\n".join(lines) + "\nEND\n"


def derive_expected(fasta_text, structure_text):
    sequences = {}
    current_id = None
    current_parts = []

    def commit_sequence():
        if current_id is not None and current_id not in sequences:
            sequences[current_id] = "".join(current_parts)

    for raw_line in fasta_text.splitlines():
        line = raw_line.strip()
        if line.startswith(">"):
            commit_sequence()
            current_id = line[1:].strip()
            current_parts = []
        elif line and current_id is not None:
            current_parts.append(line)
    commit_sequence()

    ca_counts = {}
    for line in structure_text.splitlines():
        if line.startswith(("ATOM  ", "HETATM")) and line[12:16].strip() == "CA":
            chain = line[21].strip()
            ca_counts[chain] = ca_counts.get(chain, 0) + 1

    mean_length = sum(map(len, sequences.values())) / len(sequences)
    return {
        sequence_id: {
            "ca_count": ca_counts[sequence_id],
            "length_diff_from_mean": len(sequences[sequence_id]) - mean_length,
        }
        for sequence_id in sorted(set(sequences).intersection(ca_counts))
    }


FUZZ_CASES = [
    (
        ">Z\nMKTA\n>A\nGG\n>Z\nMMMMMMMMM\n>C\nAAAAAA\n>Q\nW\n",
        pdb_text([
            ("N", "Z", 1), ("CA", "Z", 1), ("CAX", "Z", 2),
            ("CA", "A", 1), ("CA", "A", 2), ("CA", "X", 1),
        ]),
    ),
    (
        ">D\nM\n>B\nMKTAA\n>F\nGG\n>B\nQ\n>K\nMMMM\nMMMM\n",
        pdb_text([
            ("CA", "F", 1), ("CA", "F", 2),
            ("CA", "D", 1), ("N", "D", 2), ("CA", "D", 2), ("CA", "D", 3),
            ("CA", "K", 1), ("CA", "R", 1),
        ]),
    ),
]


@pytest.mark.parametrize("fasta_text,structure_text", FUZZ_CASES)
def test_script_parses_changed_inputs(fasta_text, structure_text):
    original_fasta = FASTA_PATH.read_bytes()
    original_pdb = PDB_PATH.read_bytes()
    try:
        FASTA_PATH.write_text(fasta_text)
        PDB_PATH.write_text(structure_text)
        if JSON_PATH.exists():
            JSON_PATH.unlink()

        run_script()
        assert JSON_PATH.is_file(), "The script did not generate /home/user/features.json."

        expected = derive_expected(fasta_text, structure_text)
        with JSON_PATH.open() as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

        assert actual == expected, f"Incorrect output for changed input files. Got: {actual}; expected: {expected}"
        assert list(actual.keys()) == sorted(actual.keys()), "The keys in the output JSON file are not sorted alphabetically."
    finally:
        FASTA_PATH.write_bytes(original_fasta)
        PDB_PATH.write_bytes(original_pdb)
        if JSON_PATH.exists():
            JSON_PATH.unlink()
        run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
