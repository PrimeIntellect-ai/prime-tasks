#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_period3.py
import json
import math
import os
import secrets
import shutil
import stat
import subprocess
import sys

HOME = "/home/user"
FASTA = os.path.join(HOME, "sequence.fasta")
NOTEBOOK = os.path.join(HOME, "period3_analysis.ipynb")
SCRIPT = os.path.join(HOME, "run_analysis.sh")
RESULTS = os.path.join(HOME, "results.json")
MARKER = "/tmp/period3_notebook_executed"


def read_sequence(path=FASTA):
    with open(path, "r") as f:
        return "".join(line.strip() for line in f if not line.startswith(">"))


def expected_values(seq):
    import numpy as np

    eiip = {"A": 0.1260, "C": 0.1340, "G": 0.0806, "T": 0.1335}
    signal = np.array([eiip[b] for b in seq], dtype=float)
    n = len(signal)
    assert n > 0 and n % 3 == 0
    k = n // 3

    power = np.abs(np.fft.fft(signal)) ** 2

    np.random.seed(42)
    simulated = []
    for _ in range(1000):
        shuffled = np.random.permutation(signal)
        shuffled_power = np.abs(np.fft.fft(shuffled)) ** 2
        simulated.append(shuffled_power[k])

    p3 = round(float(power[k]), 4)
    bootstrap = round(float(np.percentile(simulated, 95)), 4)
    analytical = round(float(n * np.var(signal, ddof=0)), 4)
    return {
        "sequence_length": n,
        "period_3_power": p3,
        "bootstrap_95th_percentile": bootstrap,
        "analytical_mean_power": analytical,
        "is_coding": p3 > bootstrap,
    }


def load_results():
    assert os.path.exists(RESULTS), f"Missing results file: {RESULTS}"
    with open(RESULTS, "r") as f:
        return json.load(f)


def validate_results(results, expected, bootstrap_tolerance=0.0002):
    expected_keys = {
        "sequence_length",
        "period_3_power",
        "bootstrap_95th_percentile",
        "analytical_mean_power",
        "is_coding",
    }
    assert set(results.keys()) == expected_keys, \
        f"JSON keys do not match expected keys. Found: {list(results.keys())}"
    assert results["sequence_length"] == expected["sequence_length"]
    assert math.isclose(results["period_3_power"], expected["period_3_power"], abs_tol=0.0002)
    assert math.isclose(results["analytical_mean_power"], expected["analytical_mean_power"], abs_tol=0.0002)
    assert math.isclose(
        results["bootstrap_95th_percentile"],
        expected["bootstrap_95th_percentile"],
        abs_tol=bootstrap_tolerance,
    )
    assert isinstance(results["is_coding"], bool)
    assert results["is_coding"] == (results["period_3_power"] > results["bootstrap_95th_percentile"])
    assert results["is_coding"] == expected["is_coding"]


def run(cmd, timeout):
    completed = subprocess.run(
        cmd,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    assert completed.returncode == 0, completed.stdout[-8000:]


def main():
    # Preserve the original assertions about artifact presence and executability.
    assert os.path.exists(SCRIPT), f"Missing shell script: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Shell script is not executable: {SCRIPT}"
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"Not a regular file: {SCRIPT}"
    assert os.path.exists(NOTEBOOK), f"Missing Jupyter notebook: {NOTEBOOK}"
    assert stat.S_ISREG(os.stat(NOTEBOOK).st_mode), f"Not a regular file: {NOTEBOOK}"

    with open(FASTA, "rb") as f:
        original_fasta = f.read()
    with open(NOTEBOOK, "rb") as f:
        original_notebook = f.read()

    try:
        notebook = json.loads(original_notebook.decode("utf-8"))
        assert isinstance(notebook, dict) and isinstance(notebook.get("cells"), list), \
            "Notebook is not a valid notebook JSON document"
        code_cells = [c for c in notebook["cells"] if c.get("cell_type") == "code"]
        assert code_cells, "Notebook contains no code cells"
        source = "\n".join(
            "".join(c.get("source", [])) if isinstance(c.get("source", []), list)
            else str(c.get("source", ""))
            for c in code_cells
        ).lower()
        for required in ("sequence.fasta", "results.json", "fft", "percentile"):
            assert required in source, f"Notebook code does not contain required analysis element: {required}"

        # Add a harmless sentinel cell so execution through run_analysis.sh is observed,
        # rather than trusting that the shell script merely mentions the notebook.
        notebook["cells"].append({
            "cell_type": "code",
            "execution_count": None,
            "metadata": {},
            "outputs": [],
            "source": [
                "from pathlib import Path\n",
                f"Path({MARKER!r}).write_text('executed')\n",
            ],
        })
        with open(NOTEBOOK, "w") as f:
            json.dump(notebook, f)

        if os.path.exists(MARKER):
            os.remove(MARKER)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)

        # Execute the required orchestration script on the original input.
        run([SCRIPT], timeout=420)
        assert os.path.exists(MARKER), "run_analysis.sh did not execute period3_analysis.ipynb"

        original_seq = "".join(
            line.strip() for line in original_fasta.decode("utf-8").splitlines()
            if not line.startswith(">")
        )
        original_expected = expected_values(original_seq)
        original_results = load_results()
        validate_results(original_results, original_expected, bootstrap_tolerance=0.005)

        # Preserve the original verifier's fixed bootstrap assertion.
        assert math.isclose(original_results["bootstrap_95th_percentile"], 0.2831, abs_tol=0.005), \
            f"Expected bootstrap_95th_percentile ~0.2831, got {original_results['bootstrap_95th_percentile']}"

        # Replace the FASTA with an unpredictable divisible-by-three sequence and
        # execute the notebook itself. This rejects fixed results and proves the
        # calculations live in the notebook rather than only in the shell script.
        n = 72 + 3 * secrets.randbelow(17)
        alphabet = "ACGT"
        random_seq = "".join(alphabet[secrets.randbelow(4)] for _ in range(n))
        with open(FASTA, "w") as f:
            f.write(">dynamic verifier sequence\n")
            for i in range(0, n, 19):
                f.write(random_seq[i:i + 19] + "\n")
        if os.path.exists(RESULTS):
            os.remove(RESULTS)

        jupyter = shutil.which("jupyter")
        jupyter_nbconvert = shutil.which("jupyter-nbconvert")
        if jupyter:
            command = [jupyter, "nbconvert", "--to", "notebook", "--execute", "--inplace",
                       "--ExecutePreprocessor.timeout=240", NOTEBOOK]
        elif jupyter_nbconvert:
            command = [jupyter_nbconvert, "--to", "notebook", "--execute", "--inplace",
                       "--ExecutePreprocessor.timeout=240", NOTEBOOK]
        else:
            raise AssertionError("Notebook execution tooling was not installed by run_analysis.sh")
        run(command, timeout=300)

        dynamic_expected = expected_values(random_seq)
        dynamic_results = load_results()
        validate_results(dynamic_results, dynamic_expected)
    finally:
        with open(FASTA, "wb") as f:
            f.write(original_fasta)
        with open(NOTEBOOK, "wb") as f:
            f.write(original_notebook)
        if os.path.exists(MARKER):
            os.remove(MARKER)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_period3.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
