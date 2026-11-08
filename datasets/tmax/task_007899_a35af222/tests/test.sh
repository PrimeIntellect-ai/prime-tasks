#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import re
import subprocess
import tempfile

import pytest

VENV_PYTHON = "/home/user/venv/bin/python"
SCRIPT_PATH = "/home/user/process_alignments.py"
FASTA_PATH = "/home/user/genomics_data/sequences.fasta"
RESULTS_PATH = "/home/user/results.csv"
STATS_PATH = "/home/user/model_stats.txt"


def _expected_results():
    helper = r'''
import json
import numpy as np
from Bio import Align, SeqIO
from Bio.SeqUtils import gc_fraction
from sklearn.linear_model import LinearRegression

primer = "CGTAGCTAGCC"
aligner = Align.PairwiseAligner()
aligner.mode = "local"
aligner.match_score = 2
aligner.mismatch_score = -1
aligner.open_gap_score = -2
aligner.extend_gap_score = -0.5

rows = []
X = []
y = []
for record in SeqIO.parse("/home/user/genomics_data/sequences.fasta", "fasta"):
    sequence = str(record.seq)
    gc = gc_fraction(sequence) * 100.0
    score = float(aligner.score(primer, sequence))
    rows.append([record.id, gc, score])
    X.append(gc)
    y.append(score)

model = LinearRegression()
model.fit(np.asarray(X).reshape(-1, 1), np.asarray(y))
print(json.dumps({
    "rows": rows,
    "slope": float(model.coef_[0]),
    "intercept": float(model.intercept_),
}))
'''
    result = subprocess.run(
        [VENV_PYTHON, "-c", helper], capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, (
        "Failed to compute expected results using the user's virtual environment. "
        "Are biopython and scikit-learn installed?\n" + result.stderr
    )
    return json.loads(result.stdout.strip())


def _assert_multiprocessing_imported(source):
    tree = ast.parse(source, filename=SCRIPT_PATH)
    found = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name == "multiprocessing" or alias.name.startswith("multiprocessing.")
                   for alias in node.names):
                found = True
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module == "multiprocessing" or
                                node.module.startswith("multiprocessing.")):
                found = True
    assert found, "process_alignments.py does not import Python's multiprocessing module"


def _make_multiprocessing_audit(directory, audit_file):
    sitecustomize = r'''
import os

_audit_file = os.environ.get("MP_AUDIT_FILE")

def _log(value):
    if _audit_file:
        with open(_audit_file, "a") as handle:
            handle.write(value + "\n")

try:
    import multiprocessing.pool as _mp_pool
    _original_init = _mp_pool.Pool.__init__
    def _audited_init(self, *args, **kwargs):
        _log("pool_init")
        return _original_init(self, *args, **kwargs)
    _mp_pool.Pool.__init__ = _audited_init

    for _name in ("map", "map_async", "imap", "imap_unordered", "starmap",
                  "starmap_async", "apply", "apply_async"):
        if hasattr(_mp_pool.Pool, _name):
            _original = getattr(_mp_pool.Pool, _name)
            def _make_wrapper(original):
                def _wrapper(self, *args, **kwargs):
                    _log("pool_work")
                    return original(self, *args, **kwargs)
                return _wrapper
            setattr(_mp_pool.Pool, _name, _make_wrapper(_original))
except Exception:
    pass

try:
    import multiprocessing.process as _mp_process
    _original_start = _mp_process.BaseProcess.start
    def _audited_start(self, *args, **kwargs):
        _log("process_start")
        return _original_start(self, *args, **kwargs)
    _mp_process.BaseProcess.start = _audited_start
except Exception:
    pass
'''
    with open(os.path.join(directory, "sitecustomize.py"), "w") as handle:
        handle.write(sitecustomize)
    open(audit_file, "w").close()


@pytest.fixture(scope="session")
def completed_run():
    assert os.path.exists(VENV_PYTHON), (
        "Virtual environment python binary not found at /home/user/venv/bin/python"
    )
    assert os.path.isfile(SCRIPT_PATH), (
        "Processing script not found at /home/user/process_alignments.py"
    )

    with open(SCRIPT_PATH, "r") as handle:
        source = handle.read()
    _assert_multiprocessing_imported(source)

    expected = _expected_results()
    expected_ids = [row[0] for row in expected["rows"]]
    assert len(expected_ids) == 100, "The supplied FASTA must contain exactly 100 records"
    assert set(expected_ids) == {f"seq_{i}" for i in range(1, 101)}, (
        "The supplied FASTA sequence IDs are not the expected seq_1 through seq_100"
    )
    assert len(set(expected_ids)) == 100, "The supplied FASTA contains duplicate IDs"

    for path in (RESULTS_PATH, STATS_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with tempfile.TemporaryDirectory() as audit_dir:
        audit_file = os.path.join(audit_dir, "events.log")
        _make_multiprocessing_audit(audit_dir, audit_file)
        env = os.environ.copy()
        env["PYTHONPATH"] = audit_dir + (
            os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
        )
        env["MP_AUDIT_FILE"] = audit_file
        try:
            result = subprocess.run(
                [VENV_PYTHON, SCRIPT_PATH],
                cwd="/home/user",
                env=env,
                capture_output=True,
                text=True,
                timeout=120,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("process_alignments.py did not finish within 120 seconds")

        assert result.returncode == 0, (
            "process_alignments.py failed when executed with the virtual environment.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        with open(audit_file, "r") as handle:
            events = [line.strip() for line in handle if line.strip()]
        used_pool = "pool_init" in events and "pool_work" in events
        used_processes = "pool_init" not in events and events.count("process_start") >= 2
        assert used_pool or used_processes, (
            "The executed script did not process work in parallel using multiprocessing"
        )

    return expected


def test_venv_exists(completed_run):
    assert os.path.exists(VENV_PYTHON), (
        "Virtual environment python binary not found at /home/user/venv/bin/python"
    )


def test_script_exists(completed_run):
    assert os.path.exists(SCRIPT_PATH), (
        "Processing script not found at /home/user/process_alignments.py"
    )


def test_results_csv_exists_and_format(completed_run):
    assert os.path.exists(RESULTS_PATH), "results.csv missing"

    with open(RESULTS_PATH, "r", newline="") as handle:
        reader = csv.reader(handle)
        headers = next(reader, None)
        assert headers == ["sequence_id", "gc_content", "alignment_score"], (
            "results.csv headers are incorrect"
        )
        rows = list(reader)

    assert len(rows) > 0, "results.csv is empty"
    assert len(rows) == 100, f"results.csv must contain 100 data rows, found {len(rows)}"

    expected = {
        sequence_id: (f"{gc:.4f}", f"{score:.4f}")
        for sequence_id, gc, score in completed_run["rows"]
    }
    seen = set()
    four_decimals = re.compile(r"^-?\d+\.\d{4}$")

    for row in rows:
        assert len(row) == 3, f"Row {row} does not have exactly 3 columns"
        try:
            float(row[1])
            float(row[2])
        except ValueError:
            pytest.fail(f"Could not parse gc_content or alignment_score as float in row: {row}")

        sequence_id, gc_text, score_text = row
        assert sequence_id in expected, f"Unexpected sequence ID in results.csv: {sequence_id}"
        assert sequence_id not in seen, f"Duplicate sequence ID in results.csv: {sequence_id}"
        seen.add(sequence_id)
        assert four_decimals.fullmatch(gc_text), (
            f"GC content for {sequence_id} is not formatted to exactly 4 decimal places"
        )
        assert four_decimals.fullmatch(score_text), (
            f"Alignment score for {sequence_id} is not formatted to exactly 4 decimal places"
        )
        assert (gc_text, score_text) == expected[sequence_id], (
            f"Incorrect values for {sequence_id}: expected {expected[sequence_id]}, "
            f"got {(gc_text, score_text)}"
        )

    assert seen == set(expected), "results.csv does not contain every FASTA sequence exactly once"


def test_model_stats_and_correctness(completed_run):
    assert os.path.exists(STATS_PATH), "model_stats.txt missing"

    with open(STATS_PATH, "r") as handle:
        content = handle.read()

    slope_match = re.search(r"Slope:\s*(-?\d+\.\d{4})", content)
    intercept_match = re.search(r"Intercept:\s*(-?\d+\.\d{4})", content)
    assert slope_match, "model_stats.txt does not contain correctly formatted Slope"
    assert intercept_match, "model_stats.txt does not contain correctly formatted Intercept"
    assert re.fullmatch(
        r"Slope: -?\d+\.\d{4}\nIntercept: -?\d+\.\d{4}\n?", content
    ), "model_stats.txt must contain exactly the two required, four-decimal lines"

    actual_slope = float(slope_match.group(1))
    actual_intercept = float(intercept_match.group(1))
    expected_slope = round(completed_run["slope"], 4)
    expected_intercept = round(completed_run["intercept"], 4)

    assert math.isclose(actual_slope, expected_slope, abs_tol=0.0002), (
        f"Slope mismatch. Expected {expected_slope}, got {actual_slope}"
    )
    assert math.isclose(actual_intercept, expected_intercept, abs_tol=0.0002), (
        f"Intercept mismatch. Expected {expected_intercept}, got {actual_intercept}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
