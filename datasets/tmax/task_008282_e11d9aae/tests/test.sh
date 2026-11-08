#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import h5py
import numpy as np

SCRIPT_PATH = "/home/user/prepare_features.py"
FASTA_PATH = "/home/user/data/sequences.fasta"
H5_PATH = "/home/user/data/features.h5"
MAPPING = {"A": 1.0, "C": 2.0, "G": 3.0, "T": 4.0, "N": 0.0}


def parse_fasta(path):
    records = {}
    current_id = None
    parts = []
    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current_id is not None:
                    records[current_id] = "".join(parts)
                current_id = line[1:].split()[0]
                parts = []
            else:
                assert current_id is not None, "Sequence data appeared before a FASTA header"
                parts.append(line)
    if current_id is not None:
        records[current_id] = "".join(parts)
    return records


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Preparation script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def verify_hdf5(records):
    assert os.path.isfile(H5_PATH), f"Expected output file {H5_PATH} does not exist."
    with h5py.File(H5_PATH, "r") as h5_file:
        assert set(h5_file.keys()) == set(records), (
            f"Root datasets {sorted(h5_file.keys())} do not match FASTA IDs {sorted(records)}"
        )
        for sequence_id, sequence in records.items():
            obj = h5_file[sequence_id]
            assert isinstance(obj, h5py.Dataset), f"'{sequence_id}' is not a root-level dataset"
            assert obj.dtype == np.dtype("float64"), (
                f"Dataset '{sequence_id}' should have dtype float64, got {obj.dtype}"
            )
            assert obj.compression is None, f"Dataset '{sequence_id}' must not be compressed"
            mapped = np.asarray([MAPPING[base] for base in sequence], dtype=np.float64)
            expected = np.abs(np.fft.fft(mapped))
            actual = obj[:]
            assert actual.shape == expected.shape, (
                f"Dataset '{sequence_id}' has shape {actual.shape}, expected {expected.shape}"
            )
            np.testing.assert_allclose(actual, expected, rtol=1e-5, atol=1e-8)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."


def test_script_executes_and_generates_features_from_fasta():
    original_fasta = open(FASTA_PATH, "rb").read()
    original_records = parse_fasta(FASTA_PATH)
    assert set(original_records) == {"seq1", "seq2", "seq3"}

    # Execute the submitted artifact and retain the original content assertions.
    run_script()
    verify_hdf5(original_records)

    # Exercise parsing and feature generation on unpredictable records so a
    # precomputed HDF5 file or fixed-output script cannot pass.
    alphabet = "ACGTN"
    random_records = {
        "probe_" + secrets.token_hex(6): "".join(secrets.choice(alphabet) for _ in range(length))
        for length in (7, 11, 17)
    }
    random_fasta = "".join(
        ">{}\n{}\n{}\n".format(sequence_id, sequence[:3], sequence[3:])
        for sequence_id, sequence in random_records.items()
    )

    try:
        with open(FASTA_PATH, "w", encoding="utf-8") as handle:
            handle.write(random_fasta)
        run_script()
        verify_hdf5(random_records)
    finally:
        with open(FASTA_PATH, "wb") as handle:
            handle.write(original_fasta)
        run_script()

    # Leave and verify the requested final artifact for the original FASTA.
    verify_hdf5(original_records)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
