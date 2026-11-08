#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import subprocess
from collections import Counter


def parse_fasta(path):
    records = []
    current_id = None
    sequence_parts = []

    with open(path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current_id is not None:
                    records.append((current_id, "".join(sequence_parts)))
                current_id = line[1:].strip()
                assert current_id, f"FASTA file {path} contains an empty sequence ID."
                sequence_parts = []
            else:
                assert current_id is not None, f"FASTA file {path} has sequence data before a header."
                sequence_parts.append(line)

    if current_id is not None:
        records.append((current_id, "".join(sequence_parts)))
    return records


def gc_ratio(sequence):
    valid = [base for base in sequence.upper() if base in "ATGC"]
    if not valid:
        return 0.0
    return (valid.count("G") + valid.count("C")) / len(valid)


def test_chunks_directory_exists():
    path = "/home/user/chunks"
    assert os.path.isdir(path), f"Directory {path} was not created."


def test_chunks_files_exist():
    path = "/home/user/chunks"
    assert os.path.isdir(path), f"Directory {path} was not created."
    files = glob.glob(os.path.join(path, "*.fa"))
    assert len(files) >= 6, f"Expected at least 6 .fa files in {path}, found {len(files)}."


def test_high_gc_anomalies_file_contents():
    path = "/home/user/high_gc_anomalies.txt"
    assert os.path.isfile(path), f"Output file {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["Seq2_High", "Seq4_High", "Seq5_Border"]

    assert lines == expected, f"File {path} does not contain the correct sorted sequence IDs. Expected: {expected}, Got: {lines}"


def test_chunks_are_an_exact_individual_sequence_split():
    source_records = parse_fasta("/home/user/sequences.fasta")
    chunk_files = sorted(glob.glob("/home/user/chunks/*.fa"))

    assert len(chunk_files) == len(source_records), (
        f"Expected exactly one .fa file for each of the {len(source_records)} source sequences, "
        f"found {len(chunk_files)}."
    )

    chunk_records = []
    for path in chunk_files:
        records = parse_fasta(path)
        assert len(records) == 1, f"Chunk {path} must contain exactly one FASTA sequence."
        chunk_records.extend(records)

    assert Counter(chunk_records) == Counter(source_records), (
        "The .fa chunks are not an exact one-file-per-sequence decomposition of sequences.fasta."
    )


def test_every_chunk_runs_through_calc_gc_with_xargs_parallelism():
    script = "/home/user/calc_gc.py"
    assert os.path.isfile(script), f"Analysis script {script} is missing."
    assert os.access(script, os.X_OK), f"Analysis script {script} is not executable."

    chunk_files = sorted(glob.glob("/home/user/chunks/*.fa"))
    nul_separated_paths = b"\0".join(os.fsencode(path) for path in chunk_files) + b"\0"
    result = subprocess.run(
        ["xargs", "-0", "-n", "1", "-P", "4", script],
        input=nul_separated_paths,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert result.returncode == 0, (
        "Running calc_gc.py on every chunk with xargs -P 4 failed: "
        + result.stderr.decode(errors="replace")
    )

    output_lines = [line for line in result.stdout.decode().splitlines() if line.strip()]
    assert len(output_lines) == len(chunk_files), (
        f"calc_gc.py produced {len(output_lines)} result lines for {len(chunk_files)} chunks."
    )

    observed = {}
    for line in output_lines:
        fields = line.split("\t")
        assert len(fields) == 2, f"Unexpected calc_gc.py output line: {line!r}"
        seq_id, ratio_text = fields
        assert seq_id not in observed, f"Duplicate calc_gc.py result for sequence {seq_id}."
        try:
            observed[seq_id] = float(ratio_text)
        except ValueError:
            raise AssertionError(f"Invalid GC ratio in calc_gc.py output: {line!r}")

    expected = {}
    for path in chunk_files:
        seq_id, sequence = parse_fasta(path)[0]
        expected[seq_id] = float(f"{gc_ratio(sequence):.4f}")

    assert observed == expected, (
        f"calc_gc.py results for the submitted chunks are incorrect. Expected {expected}, got {observed}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
