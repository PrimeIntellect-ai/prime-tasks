#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import cmath
import json
import os
import random
import subprocess
import uuid

import pytest

VENV = "/home/user/bioenv"
PYTHON = os.path.join(VENV, "bin", "python")
SOURCE_NOTEBOOK = "/home/user/sequence_analysis.ipynb"
EXECUTED_NOTEBOOK = "/home/user/sequence_analysis_executed.ipynb"
FASTA = "/home/user/input/sequences.fasta"
RESULTS = "/home/user/results.json"


def load_json(path):
    with open(path, "r") as handle:
        return json.load(handle)


def test_virtual_environment_exists():
    """Test that the virtual environment was created at /home/user/bioenv."""
    assert os.path.isdir(VENV), f"Virtual environment directory {VENV} does not exist."
    assert os.path.isfile(PYTHON), f"Python executable not found at {PYTHON}. Is it a valid virtual environment?"


def test_required_packages_are_installed_in_real_venv():
    probe = r'''
import importlib.metadata as md
import json
import os
import sys
import numpy as np
import Bio
from Bio import SeqIO
import jupyter
import papermill

assert sys.prefix == os.path.realpath("/home/user/bioenv")
assert sys.base_prefix != sys.prefix
assert np.allclose(np.abs(np.fft.fft([1.0, 2.0])) ** 2, [9.0, 1.0])
assert callable(papermill.execute_notebook)
versions = {name: md.version(name) for name in ("numpy", "biopython", "jupyter", "papermill")}
print(json.dumps(versions))
'''
    completed = subprocess.run(
        [PYTHON, "-c", probe], text=True, capture_output=True, timeout=30
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    versions = json.loads(completed.stdout.strip().splitlines()[-1])
    assert set(versions) == {"numpy", "biopython", "jupyter", "papermill"}
    assert all(isinstance(value, str) and value for value in versions.values())


def test_notebooks_exist():
    """Test that both the original and executed notebooks exist."""
    assert os.path.isfile(SOURCE_NOTEBOOK), f"Original notebook {SOURCE_NOTEBOOK} does not exist."
    assert os.path.isfile(EXECUTED_NOTEBOOK), f"Executed notebook {EXECUTED_NOTEBOOK} does not exist."

    for path in (SOURCE_NOTEBOOK, EXECUTED_NOTEBOOK):
        try:
            notebook = load_json(path)
        except json.JSONDecodeError:
            pytest.fail(f"Notebook {path} is not a valid JSON file.")
        assert isinstance(notebook, dict)
        assert isinstance(notebook.get("cells"), list), f"{path} is not a Jupyter notebook structure"
        assert isinstance(notebook.get("metadata"), dict)
        assert isinstance(notebook.get("nbformat"), int)

    source = load_json(SOURCE_NOTEBOOK)
    code_cells = [cell for cell in source["cells"] if cell.get("cell_type") == "code"]
    assert code_cells, "The source notebook contains no code cells."
    assert any("".join(cell.get("source", [])).strip() for cell in code_cells), "Notebook code cells are empty."


def test_results_json_exists_and_correct():
    """Preserve the original assertions for the supplied FASTA input."""
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} does not exist."
    try:
        results = load_json(RESULTS)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS} is not a valid JSON file.")

    expected_keys = {"best_seq_id", "forward_primer", "reverse_primer", "stability_passed"}
    assert set(results.keys()) == expected_keys, f"Keys in results.json do not match expected keys. Found: {list(results.keys())}"
    assert results["best_seq_id"] == "seq_02_coding", f"Expected best_seq_id to be 'seq_02_coding', got {results['best_seq_id']}"
    assert results["forward_primer"] == "ATGATGATGATGATGATGAT", f"Expected forward_primer to be 'ATGATGATGATGATGATGAT', got {results['forward_primer']}"
    assert results["reverse_primer"] == "CATCATCATCATCATCATCA", f"Expected reverse_primer to be 'CATCATCATCATCATCATCA', got {results['reverse_primer']}"
    assert results["stability_passed"] is True, f"Expected stability_passed to be True, got {results['stability_passed']}"


def period_three_power(sequence):
    values = [{"A": 1.0, "C": 2.0, "G": 3.0, "T": 4.0}[base] for base in sequence]
    n = len(values)
    k = n // 3
    fft_value = sum(value * cmath.exp(-2j * cmath.pi * k * index / n)
                    for index, value in enumerate(values))
    return abs(fft_value) ** 2


def reverse_complement(sequence):
    return sequence.translate(str.maketrans("ACGT", "TGCA"))[::-1]


def test_z_source_notebook_executes_and_computes_unseen_input():
    suffix = uuid.uuid4().hex
    candidate_id = "spectral_" + suffix
    constant_id = "constant_" + uuid.uuid4().hex
    period_two_id = "period2_" + uuid.uuid4().hex

    sequences = {
        candidate_id: "ATG" * 60,
        constant_id: "C" * 180,
        period_two_id: "AC" * 90,
    }
    records = list(sequences.items())
    random.SystemRandom().shuffle(records)
    with open(FASTA, "w") as handle:
        for record_id, sequence in records:
            handle.write(f">{record_id}\n{sequence}\n")

    strengths = {record_id: period_three_power(sequence)
                 for record_id, sequence in sequences.items()}
    expected_id = max(strengths, key=strengths.get)
    assert expected_id == candidate_id
    expected_sequence = sequences[expected_id]

    for path in (RESULTS, EXECUTED_NOTEBOOK):
        if os.path.exists(path):
            os.remove(path)

    completed = subprocess.run(
        [PYTHON, "-m", "papermill", SOURCE_NOTEBOOK, EXECUTED_NOTEBOOK],
        text=True,
        capture_output=True,
        timeout=180,
        cwd="/home/user",
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert os.path.isfile(EXECUTED_NOTEBOOK), "Papermill did not create the required executed notebook."
    assert os.path.isfile(RESULTS), "Executing the notebook did not create results.json."

    executed = load_json(EXECUTED_NOTEBOOK)
    code_cells = [cell for cell in executed.get("cells", []) if cell.get("cell_type") == "code"]
    assert code_cells
    assert any(cell.get("execution_count") is not None for cell in code_cells), "Executed notebook has no executed code cells."
    papermill_metadata = executed.get("metadata", {}).get("papermill")
    assert isinstance(papermill_metadata, dict), "Executed notebook lacks papermill provenance metadata."
    assert papermill_metadata.get("exception") is False, "Papermill recorded an execution exception."

    results = load_json(RESULTS)
    expected_keys = {"best_seq_id", "forward_primer", "reverse_primer", "stability_passed"}
    assert set(results) == expected_keys
    assert type(results["best_seq_id"]) is str
    assert type(results["forward_primer"]) is str
    assert type(results["reverse_primer"]) is str
    assert type(results["stability_passed"]) is bool
    assert results["best_seq_id"] == expected_id
    assert results["forward_primer"] == expected_sequence[:20]
    assert results["reverse_primer"] == reverse_complement(expected_sequence[-20:])
    assert results["stability_passed"] is True
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
