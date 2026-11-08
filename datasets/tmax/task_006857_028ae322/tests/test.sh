#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import subprocess

import numpy as np
from PIL import Image

HOME = "/home/user"
NOTEBOOK = os.path.join(HOME, "analysis.ipynb")
FASTA = os.path.join(HOME, "sequences.fasta")
REFERENCE = os.path.join(HOME, "reference_variances.csv")
PNG = os.path.join(HOME, "variance_comparison.png")
CONVERGED = os.path.join(HOME, "converged_W.txt")
WINDOWS = list(range(10, 101, 10))


def parse_fasta(path):
    sequences = []
    current = []
    with open(path) as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current:
                    sequences.append("".join(current).upper())
                    current = []
            else:
                current.append(line)
    if current:
        sequences.append("".join(current).upper())
    return sequences


def stable_variances(sequences):
    result = {}
    for window_size in WINDOWS:
        values = []
        for sequence in sequences:
            assert len(sequence) >= window_size
            for start in range(len(sequence) - window_size + 1):
                window = sequence[start:start + window_size]
                values.append((window.count("G") + window.count("C")) / window_size)
        result[window_size] = float(np.var(np.asarray(values, dtype=np.float64), ddof=0))
    return result


def read_references(path):
    rows = {}
    with open(path) as f:
        header = f.readline().strip().split(",")
        assert header == ["WindowSize", "ReferenceVariance"]
        for line in f:
            if line.strip():
                w, value = line.strip().split(",")
                rows[int(w)] = float(value)
    return rows


def expected_convergence():
    calculated = stable_variances(parse_fasta(FASTA))
    references = read_references(REFERENCE)
    matches = [w for w in WINDOWS if abs(calculated[w] - references[w]) < 1e-6]
    assert matches, "The verifier dataset has no converged window"
    return min(matches)


def write_trial(seed, target):
    rng = random.Random(seed)
    alphabet = "ACGT"
    sequences = []
    for index, length in enumerate((173, 191, 217, 229)):
        sequence = "".join(rng.choices(alphabet, weights=(31 + index, 17, 25, 27), k=length))
        sequences.append(sequence)

    with open(FASTA, "w") as f:
        for index, sequence in enumerate(sequences):
            f.write(f">trial_{seed}_{index}\n")
            for start in range(0, len(sequence), 47):
                f.write(sequence[start:start + 47] + "\n")

    calculated = stable_variances(sequences)
    with open(REFERENCE, "w") as f:
        f.write("WindowSize,ReferenceVariance\n")
        for w in WINDOWS:
            if w == target:
                reference = calculated[w]
            else:
                # Every non-target difference is safely above the tolerance.
                reference = calculated[w] + (4.0e-5 + w * 1.0e-7)
            f.write(f"{w},{reference:.15g}\n")


def execute_notebook():
    for path in (PNG, CONVERGED):
        if os.path.exists(path):
            os.remove(path)
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    process = subprocess.run(
        [
            "jupyter", "nbconvert", "--to", "notebook", "--execute", "--inplace",
            "--ExecutePreprocessor.timeout=180", NOTEBOOK,
        ],
        cwd=HOME,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    assert process.returncode == 0, "Notebook execution failed:\n" + process.stdout


def inspect_outputs(expected_w):
    assert os.path.isfile(CONVERGED), "Notebook did not create converged_W.txt"
    with open(CONVERGED) as f:
        text = f.read().strip()
    assert text == str(expected_w), f"Expected convergence {expected_w}, got {text!r}"

    assert os.path.isfile(PNG), "Notebook did not create variance_comparison.png"
    assert os.path.getsize(PNG) > 8, "Plot file is empty or only a PNG header"
    with Image.open(PNG) as image:
        image.verify()
    with Image.open(PNG) as image:
        image.load()
        assert image.format == "PNG"
        assert image.width >= 100 and image.height >= 100
        pixels = image.convert("RGB").tobytes()
        assert len(set(pixels)) > 8, "Plot image has no meaningful visual content"
        return hashlib.sha256(pixels).hexdigest()


def test_notebook_executes_and_computes_from_inputs():
    assert os.path.isfile(NOTEBOOK), f"Missing file: {NOTEBOOK}"
    original_fasta = open(FASTA, "rb").read()
    original_reference = open(REFERENCE, "rb").read()
    plot_hashes = []
    try:
        # Hidden behavioral trials force the notebook to parse FASTA, calculate
        # stable rolling variances, compare references, and determine convergence.
        for seed, target in ((7319, 30), (9923, 80)):
            write_trial(seed, target)
            assert expected_convergence() == target
            execute_notebook()
            plot_hashes.append(inspect_outputs(target))

        with open(FASTA, "wb") as f:
            f.write(original_fasta)
        with open(REFERENCE, "wb") as f:
            f.write(original_reference)

        assert expected_convergence() == 60
        execute_notebook()
        plot_hashes.append(inspect_outputs(60))
        assert len(set(plot_hashes)) == len(plot_hashes), (
            "The saved plot did not respond to changed sequence/reference data"
        )

        with open(NOTEBOOK) as f:
            executed_nb = json.load(f)
        code_cells = [c for c in executed_nb.get("cells", []) if c.get("cell_type") == "code"]
        assert code_cells, "Notebook contains no code cells"
        assert any(c.get("execution_count") is not None for c in code_cells), (
            "Notebook was not saved with evidence of execution"
        )
    finally:
        with open(FASTA, "wb") as f:
            f.write(original_fasta)
        with open(REFERENCE, "wb") as f:
            f.write(original_reference)


def test_analysis_notebook_exists():
    path = "/home/user/analysis.ipynb"
    assert os.path.isfile(path), f"Missing file: {path}"

    # Basic check to see if it's a valid JSON/Notebook
    try:
        with open(path, 'r') as f:
            nb = json.load(f)
        assert "cells" in nb, f"Invalid notebook format in {path}: missing 'cells'"
    except json.JSONDecodeError:
        assert False, f"File {path} is not a valid JSON/Jupyter notebook."


def test_variance_comparison_png_exists():
    path = "/home/user/variance_comparison.png"
    assert os.path.isfile(path), f"Missing file: {path}"
    assert os.path.getsize(path) > 0, f"File {path} is empty."

    # Check PNG magic number
    with open(path, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f"File {path} is not a valid PNG image."


def test_converged_w_txt_content():
    path = "/home/user/converged_W.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content == "60", f"Expected converged_W.txt to contain '60', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
