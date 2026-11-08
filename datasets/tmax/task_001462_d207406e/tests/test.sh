#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hooks
cat << 'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import json
import os

PROCESS_LOG = "/tmp/verifier_processes.log"
PLOT_LOG = "/tmp/verifier_plots.log"

try:
    import multiprocessing.process
    _original_start = multiprocessing.process.BaseProcess.start

    def _audited_start(self, *args, **kwargs):
        with open(PROCESS_LOG, "a") as f:
            f.write(f"{os.getpid()} start {getattr(self, 'name', '')}\n")
        return _original_start(self, *args, **kwargs)

    multiprocessing.process.BaseProcess.start = _audited_start
except Exception:
    pass

try:
    import numpy as np
    from matplotlib.axes import Axes
    from matplotlib.figure import Figure

    def _record_plot(kind, x, y):
        try:
            y_arr = np.asarray(y, dtype=float).reshape(-1)
            x_arr = None if x is None else np.asarray(x, dtype=float).reshape(-1)
            record = {
                "kind": kind,
                "pid": os.getpid(),
                "x": None if x_arr is None else x_arr.tolist(),
                "y": y_arr.tolist(),
            }
            with open(PLOT_LOG, "a") as f:
                f.write(json.dumps(record) + "\n")
        except Exception:
            pass

    _original_plot = Axes.plot
    def _audited_plot(self, *args, **kwargs):
        if len(args) >= 2:
            _record_plot("plot", args[0], args[1])
        elif len(args) == 1:
            _record_plot("plot", None, args[0])
        return _original_plot(self, *args, **kwargs)
    Axes.plot = _audited_plot

    _original_stem = Axes.stem
    def _audited_stem(self, *args, **kwargs):
        if len(args) >= 2:
            _record_plot("stem", args[0], args[1])
        elif len(args) == 1:
            _record_plot("stem", None, args[0])
        return _original_stem(self, *args, **kwargs)
    Axes.stem = _audited_stem

    _original_bar = Axes.bar
    def _audited_bar(self, *args, **kwargs):
        if len(args) >= 2:
            _record_plot("bar", args[0], args[1])
        return _original_bar(self, *args, **kwargs)
    Axes.bar = _audited_bar

    _original_savefig = Figure.savefig
    def _audited_savefig(self, fname, *args, **kwargs):
        try:
            with open(PLOT_LOG, "a") as f:
                f.write(json.dumps({"kind": "savefig", "pid": os.getpid(), "path": os.fspath(fname)}) + "\n")
        except Exception:
            pass
        return _original_savefig(self, fname, *args, **kwargs)
    Figure.savefig = _audited_savefig
except Exception:
    pass
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import shutil
import subprocess

import numpy as np
import pytest

FASTA_PATH = "/home/user/data/sequences.fasta"
EXPECTED_FASTA = b'''>SeqA_periodic
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
>SeqB_flat
TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT
>SeqC_random
GCTAGCTAGCATCGTAGCTAGCTACGATCGATCGTACGATCGTAGCTACGATCGTAGCTACGATCGTAGCTACGATCGTAGCTACGATCGTAGCTACGATCGTAGCTACGATCGTAGCTA
'''
MAPPING = {"A": 0.25, "C": 0.50, "G": 0.75, "T": 1.00}


def parse_fasta_bytes(data):
    records = {}
    current = None
    for raw_line in data.decode("ascii").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith(">"):
            current = line[1:].split()[0]
            assert current not in records
            records[current] = ""
        else:
            assert current is not None
            records[current] += line
    return records


TRUSTED_SEQUENCES = parse_fasta_bytes(EXPECTED_FASTA)


def expected_spectra():
    result = {}
    for seq_id, sequence in TRUSTED_SEQUENCES.items():
        signal = np.asarray([MAPPING[base] for base in sequence], dtype=float)
        result[seq_id] = np.abs(np.fft.fft(signal)) ** 2
    return result


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_fresh():
    assert os.path.isfile("/home/user/pipeline.py"), "/home/user/pipeline.py is missing."
    assert os.path.isfile("/home/user/test_pipeline.py"), "/home/user/test_pipeline.py is missing."
    with open(FASTA_PATH, "rb") as f:
        assert f.read() == EXPECTED_FASTA, "The input FASTA file was modified."

    shutil.rmtree("/home/user/output", ignore_errors=True)
    for marker in ("/tmp/verifier_processes.log", "/tmp/verifier_plots.log"):
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = "/tmp/verifier_hooks" + ((":" + old_pythonpath) if old_pythonpath else "")
    result = subprocess.run(
        ["python3", "/home/user/pipeline.py"],
        cwd="/home/user",
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Pipeline execution failed:\n{result.stdout}\n{result.stderr}"


def test_files_exist():
    assert os.path.isfile("/home/user/pipeline.py"), "/home/user/pipeline.py is missing."
    assert os.path.isfile("/home/user/test_pipeline.py"), "/home/user/test_pipeline.py is missing."
    assert os.path.isdir("/home/user/output"), "/home/user/output directory is missing."
    assert os.path.isfile("/home/user/output/results.csv"), "/home/user/output/results.csv is missing."
    assert os.path.isfile("/home/user/output/top_spectrum.png"), "/home/user/output/top_spectrum.png is missing."


def test_results_csv_content():
    csv_path = "/home/user/output/results.csv"
    with open(csv_path, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, "results.csv is empty."
    expected_header = ["SequenceID", "MaxPowerIndex", "MaxPowerValue"]
    assert rows[0] == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {rows[0]}."

    data_rows = rows[1:]
    assert len(data_rows) == 3, f"Expected 3 data rows in CSV, got {len(data_rows)}."
    assert all(len(row) == 3 for row in data_rows), "Every CSV data row must have exactly three columns."

    seq_ids = [row[0] for row in data_rows]
    assert seq_ids == sorted(seq_ids), "CSV rows are not sorted alphabetically by SequenceID."
    assert len(set(seq_ids)) == 3, "CSV contains duplicate SequenceID rows."

    results = {row[0]: {"index": int(row[1]), "value": float(row[2])} for row in data_rows}
    assert "SeqA_periodic" in results, "SeqA_periodic missing from results."
    assert "SeqB_flat" in results, "SeqB_flat missing from results."
    assert "SeqC_random" in results, "SeqC_random missing from results."
    assert set(results) == set(TRUSTED_SEQUENCES), "CSV contains missing or unexpected sequence IDs."

    spectra = expected_spectra()
    for seq_id, power in spectra.items():
        non_dc = power[1:]
        expected_value = float(np.max(non_dc))
        tied_indices = np.flatnonzero(np.isclose(power, expected_value, rtol=1e-10, atol=1e-10))
        tied_indices = set(int(i) for i in tied_indices if i != 0)
        assert results[seq_id]["index"] in tied_indices, (
            f"{seq_id} MaxPowerIndex is incorrect: got {results[seq_id]['index']}, "
            f"expected one of {sorted(tied_indices)}."
        )
        rounded = round(expected_value, 4)
        assert abs(results[seq_id]["value"] - rounded) <= 0.00005, (
            f"{seq_id} MaxPowerValue is incorrect: got {results[seq_id]['value']}, expected {rounded}."
        )

    assert results["SeqA_periodic"]["index"] in [30, 90]
    assert abs(results["SeqA_periodic"]["value"] - 450.0) <= 0.00005
    assert abs(results["SeqB_flat"]["value"]) < 0.001


def test_png_is_valid_and_contains_top_spectrum():
    png_path = "/home/user/output/top_spectrum.png"
    with open(png_path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "top_spectrum.png is not a valid PNG file."

    import matplotlib.image as mpimg
    image = mpimg.imread(png_path)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
    assert float(np.max(image)) > float(np.min(image)), "The PNG image is blank."

    spectra = expected_spectra()
    maxima = {seq_id: float(np.max(power[1:])) for seq_id, power in spectra.items()}
    top_id = max(maxima, key=maxima.get)
    expected_power = spectra[top_id]

    assert os.path.isfile("/tmp/verifier_plots.log"), "No matplotlib plotting operation was observed."
    records = []
    with open("/tmp/verifier_plots.log") as f:
        for line in f:
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pass

    assert any(r.get("kind") == "savefig" and os.path.abspath(r.get("path", "")) == png_path for r in records), (
        "The pipeline did not save the matplotlib figure to top_spectrum.png."
    )

    matched = False
    for record in records:
        if record.get("kind") not in {"plot", "stem", "bar"} or not isinstance(record.get("y"), list):
            continue
        y = np.asarray(record["y"], dtype=float)
        candidates = [(expected_power, np.arange(len(expected_power), dtype=float))]
        candidates.append((expected_power[1:], np.arange(1, len(expected_power), dtype=float)))
        for expected_y, expected_x in candidates:
            if y.shape != expected_y.shape or not np.allclose(y, expected_y, rtol=1e-6, atol=1e-6):
                continue
            x_data = record.get("x")
            if x_data is None:
                matched = True
            else:
                x = np.asarray(x_data, dtype=float)
                if x.shape == expected_x.shape and np.allclose(x, expected_x, rtol=0, atol=1e-9):
                    matched = True
            if matched:
                break
        if matched:
            break
    assert matched, f"The saved plot was not generated from the power spectrum of the highest-power sequence ({top_id})."


def test_multiprocessing_used():
    with open("/home/user/pipeline.py", "r") as f:
        source = f.read()
    tree = ast.parse(source)
    multiprocessing_imported = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any("multiprocessing" in alias.name for alias in node.names):
                multiprocessing_imported = True
        elif isinstance(node, ast.ImportFrom):
            if node.module and "multiprocessing" in node.module:
                multiprocessing_imported = True
    assert multiprocessing_imported, "The 'multiprocessing' module is not imported in pipeline.py."
    assert os.path.isfile("/tmp/verifier_processes.log"), "The pipeline imported multiprocessing but started no worker process."
    with open("/tmp/verifier_processes.log") as f:
        starts = [line for line in f if " start " in line]
    assert starts, "The pipeline did not actually start a multiprocessing worker."


def test_required_student_test_is_present():
    with open("/home/user/test_pipeline.py", "r") as f:
        tree = ast.parse(f.read())
    tests = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test")]
    assert tests, "test_pipeline.py contains no pytest test functions."

    qualifying = False
    for test in tests:
        constants = [node.value for node in ast.walk(test) if isinstance(node, ast.Constant)]
        has_acgt = "ACGT" in constants
        has_pipeline_import = any(
            (isinstance(node, ast.ImportFrom) and node.module == "pipeline") or
            (isinstance(node, ast.Import) and any(alias.name == "pipeline" for alias in node.names))
            for node in ast.walk(test)
        )
        has_len_four_assert = False
        for node in ast.walk(test):
            if not isinstance(node, ast.Assert):
                continue
            for part in ast.walk(node.test):
                if isinstance(part, ast.Compare):
                    values = [part.left] + list(part.comparators)
                    has_four = any(isinstance(v, ast.Constant) and v.value == 4 for v in values)
                    has_len = any(
                        isinstance(v, ast.Call) and isinstance(v.func, ast.Name) and v.func.id == "len"
                        for v in values
                    )
                    if has_four and has_len:
                        has_len_four_assert = True
        if has_acgt and has_pipeline_import and has_len_four_assert:
            qualifying = True
            break
    assert qualifying, "A pytest test must import pipeline logic, process 'ACGT', and assert that the FFT length is 4."


def test_pytest_suite_passes():
    result = subprocess.run(
        ["pytest", "/home/user/test_pipeline.py"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Student's pytest suite failed:\n{result.stdout}\n{result.stderr}"
    assert "passed" in result.stdout.lower(), "Pytest output does not indicate passing tests."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
