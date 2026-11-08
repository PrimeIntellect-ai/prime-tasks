#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /tmp/verifier_instrument

cat << 'PY_EOF' > /tmp/verifier_instrument/sitecustomize.py
import json
import os
import numpy as np

trace_path = os.environ.get("VERIFY_TRACE")

def record(event, **fields):
    if not trace_path:
        return
    with open(trace_path, "a", encoding="utf-8") as f:
        f.write(json.dumps({"event": event, **fields}) + "\n")

try:
    from scipy.stats import gamma
    _gamma_fit = gamma.fit
    _gamma_pdf = gamma.pdf

    def checked_fit(data, *args, **kwargs):
        arr = np.asarray(data, dtype=float)
        record("gamma_fit", data=arr.ravel().tolist())
        return _gamma_fit(data, *args, **kwargs)

    def checked_pdf(x, *args, **kwargs):
        arr = np.asarray(x, dtype=float)
        record("gamma_pdf", size=int(arr.size))
        return _gamma_pdf(x, *args, **kwargs)

    gamma.fit = checked_fit
    gamma.pdf = checked_pdf
except Exception:
    pass

try:
    import matplotlib
    matplotlib.use("Agg")
    from matplotlib.axes import Axes
    _axes_hist = Axes.hist
    _axes_plot = Axes.plot

    def checked_hist(self, x, *args, **kwargs):
        arr = np.asarray(x, dtype=float)
        record("hist", data=arr.ravel().tolist(), density=kwargs.get("density", None))
        return _axes_hist(self, x, *args, **kwargs)

    def checked_plot(self, *args, **kwargs):
        record("plot")
        return _axes_plot(self, *args, **kwargs)

    Axes.hist = checked_hist
    Axes.plot = checked_plot
except Exception:
    pass
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import subprocess
import sys

import matplotlib.image as mpimg
import numpy as np
import pytest
from scipy.stats import gamma

SCRIPT = "/home/user/protein_analysis.py"
STUDENT_TEST = "/home/user/test_protein_analysis.py"
FASTA = "/home/user/input/protein.fasta"
PDB = "/home/user/input/protein.pdb"
JSON_OUT = "/home/user/output/gamma_params.json"
PNG_OUT = "/home/user/output/distance_distribution.png"
INSTRUMENT = "/tmp/verifier_instrument"


def test_scripts_exist():
    assert os.path.isfile(SCRIPT), "The script /home/user/protein_analysis.py is missing."
    assert os.path.isfile(STUDENT_TEST), "The test script /home/user/test_protein_analysis.py is missing."


def test_outputs_exist():
    assert os.path.isfile(JSON_OUT), "The output JSON /home/user/output/gamma_params.json is missing."
    assert os.path.isfile(PNG_OUT), "The output plot /home/user/output/distance_distribution.png is missing."


def test_json_content():
    with open(JSON_OUT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_OUT} is not valid JSON.")

    expected_keys = {"a", "loc", "scale"}
    assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, but got {set(data.keys())}."
    for key in expected_keys:
        assert isinstance(data[key], (int, float)), f"The value for '{key}' must be a number, but got {type(data[key])}."


def test_student_pytest_passes():
    result = subprocess.run(
        [sys.executable, "-m", "pytest", STUDENT_TEST],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Running pytest on {STUDENT_TEST} failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def test_student_test_file_content():
    with open(STUDENT_TEST, "r") as f:
        content = f.read()
    assert "test_distance_computation" in content, "The test file must contain 'test_distance_computation'."
    assert "test_gamma_fit" in content, "The test file must contain 'test_gamma_fit'."


def _literal_lists(node):
    for child in ast.walk(node):
        if isinstance(child, (ast.List, ast.Tuple)):
            try:
                yield ast.literal_eval(child)
            except Exception:
                pass


def _call_name(call):
    fn = call.func
    if isinstance(fn, ast.Name):
        return fn.id
    if isinstance(fn, ast.Attribute):
        return fn.attr
    return ""


def test_student_tests_are_substantive():
    with open(STUDENT_TEST, encoding="utf-8") as f:
        tree = ast.parse(f.read())

    funcs = {n.name: n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    assert "test_distance_computation" in funcs, "test_distance_computation must be an actual test function."
    assert "test_gamma_fit" in funcs, "test_gamma_fit must be an actual test function."
    distance_test = funcs["test_distance_computation"]
    gamma_test = funcs["test_gamma_fit"]

    imported_names = set()
    module_aliases = set()
    for node in tree.body:
        if isinstance(node, ast.ImportFrom) and node.module == "protein_analysis":
            imported_names.update(alias.asname or alias.name for alias in node.names)
        elif isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "protein_analysis":
                    module_aliases.add(alias.asname or alias.name)

    def calls_analysis(node):
        for call in (x for x in ast.walk(node) if isinstance(x, ast.Call)):
            if isinstance(call.func, ast.Name) and call.func.id in imported_names:
                return True
            if (isinstance(call.func, ast.Attribute) and isinstance(call.func.value, ast.Name)
                    and call.func.value.id in module_aliases):
                return True
        return False

    assert calls_analysis(distance_test), "test_distance_computation must exercise code imported from protein_analysis."
    assert calls_analysis(gamma_test), "test_gamma_fit must exercise code imported from protein_analysis."

    arrays_3x3 = []
    for value in _literal_lists(distance_test):
        if (isinstance(value, (list, tuple)) and len(value) == 3
                and all(isinstance(row, (list, tuple)) and len(row) == 3 for row in value)):
            try:
                arr = np.asarray(value, dtype=float)
                if np.isfinite(arr).all() and len(np.unique(arr, axis=0)) > 1:
                    arrays_3x3.append(arr)
            except Exception:
                pass
    assert arrays_3x3, "test_distance_computation must contain a hardcoded numeric 3x3 coordinate array."
    assert any(_call_name(x) == "assert_allclose" for x in ast.walk(distance_test) if isinstance(x, ast.Call)), \
        "test_distance_computation must use assert_allclose to check the expected distances."

    dummy = [1.0, 2.0, 2.0, 3.0, 3.0, 3.0, 4.0, 4.0, 5.0]
    found_dummy = False
    for value in _literal_lists(gamma_test):
        if isinstance(value, (list, tuple)):
            try:
                if np.array_equal(np.asarray(value, dtype=float), np.asarray(dummy)):
                    found_dummy = True
            except Exception:
                pass
    assert found_dummy, "test_gamma_fit must use the specified dummy-distance array."

    positive_assert = False
    for assertion in (x for x in ast.walk(gamma_test) if isinstance(x, ast.Assert)):
        for comp in (x for x in ast.walk(assertion.test) if isinstance(x, ast.Compare)):
            if any(isinstance(op, ast.Gt) for op in comp.ops):
                for rhs in comp.comparators:
                    try:
                        if ast.literal_eval(rhs) == 0:
                            positive_assert = True
                    except Exception:
                        pass
    assert positive_assert, "test_gamma_fit must assert that the fitted shape parameter is greater than zero."


def _read_sequence_length(path):
    sequence = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith(">"):
                sequence.append(line)
    return len("".join(sequence))


def _read_ca_coordinates(path):
    coords = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith(("ATOM  ", "HETATM")) and line[12:16].strip() == "CA":
                coords.append([float(line[30:38]), float(line[38:46]), float(line[46:54])])
    return np.asarray(coords, dtype=float)


def _expected(path_fasta, path_pdb):
    coords = _read_ca_coordinates(path_pdb)
    assert len(coords) == _read_sequence_length(path_fasta)
    distances = np.linalg.norm(coords - coords.mean(axis=0), axis=1)
    return distances, np.asarray(gamma.fit(distances), dtype=float)


def _load_trace(path):
    events = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            events.append(json.loads(line))
    return events


def _run_and_validate(expected_distances, expected_params, label):
    for path in (JSON_OUT, PNG_OUT):
        if os.path.exists(path):
            os.remove(path)
    trace = f"/tmp/{label}_trace.jsonl"
    if os.path.exists(trace):
        os.remove(trace)
    env = os.environ.copy()
    env["PYTHONPATH"] = INSTRUMENT + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["VERIFY_TRACE"] = trace
    env["MPLBACKEND"] = "Agg"
    result = subprocess.run(
        [sys.executable, SCRIPT], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120,
    )
    assert result.returncode == 0, f"Analysis script failed on {label} input.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.isfile(JSON_OUT), "The analysis script did not generate gamma_params.json."
    assert os.path.isfile(PNG_OUT), "The analysis script did not generate distance_distribution.png."

    with open(JSON_OUT, encoding="utf-8") as f:
        actual = json.load(f)
    assert set(actual) == {"a", "loc", "scale"}
    actual_params = np.asarray([actual["a"], actual["loc"], actual["scale"]], dtype=float)
    assert np.isfinite(actual_params).all()
    assert actual_params[0] > 0 and actual_params[2] > 0
    np.testing.assert_allclose(actual_params, expected_params, rtol=1e-7, atol=1e-8,
                               err_msg="Saved Gamma parameters do not match scipy.stats.gamma.fit on the CA distances.")

    with open(PNG_OUT, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "The plot output is not a PNG file."
    assert os.path.getsize(PNG_OUT) > 1000, "The PNG plot is unexpectedly empty."
    image = mpimg.imread(PNG_OUT)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100
    assert float(np.std(image)) > 0.005, "The PNG does not contain meaningful rendered plot content."

    events = _load_trace(trace)
    fits = [e for e in events if e.get("event") == "gamma_fit"]
    hists = [e for e in events if e.get("event") == "hist"]
    assert fits, "The script did not call scipy.stats.gamma.fit."
    assert any(np.allclose(np.sort(np.asarray(e["data"])), np.sort(expected_distances)) for e in fits), \
        "Gamma fitting was not performed on the computed CA distances."
    assert hists, "The script did not create a histogram."
    assert any(e.get("density") is True and np.allclose(np.sort(np.asarray(e["data"])), np.sort(expected_distances)) for e in hists), \
        "The histogram must use the computed distances with density=True."
    assert any(e.get("event") == "gamma_pdf" and e.get("size", 0) > 1 for e in events), \
        "The script did not evaluate the fitted Gamma PDF for the overlay."
    assert any(e.get("event") == "plot" for e in events), "The script did not plot the fitted PDF overlay."


def _pdb_for(coords):
    lines = []
    for i, (x, y, z) in enumerate(coords, 1):
        lines.append(f"ATOM  {i:5d}  CA  ALA A{i:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C  \n")
    return "".join(lines)


def test_pipeline_computes_results_and_validates_lengths():
    with open(FASTA, "rb") as f:
        original_fasta = f.read()
    with open(PDB, "rb") as f:
        original_pdb = f.read()

    alternate_coords = np.asarray([
        [0, 0, 0], [1, 2, 0], [3, 1, 1], [4, 5, 2], [2, 7, 4],
        [-1, 4, 6], [-3, 0, 2], [5, -2, 3], [0, -4, -1],
    ], dtype=float)
    try:
        with open(FASTA, "w", encoding="utf-8") as f:
            f.write(">verification_variant\nACDEFGHIK\n")
        with open(PDB, "w", encoding="utf-8") as f:
            f.write(_pdb_for(alternate_coords))
        distances, params = _expected(FASTA, PDB)
        _run_and_validate(distances, params, "alternate")

        with open(FASTA, "w", encoding="utf-8") as f:
            f.write(">mismatch\nACDEFGHI\n")
        mismatch = subprocess.run(
            [sys.executable, SCRIPT], cwd="/home/user",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120,
            env={**os.environ, "MPLBACKEND": "Agg"},
        )
        assert mismatch.returncode != 0 and "ValueError" in mismatch.stderr, \
            "A CA/FASTA length mismatch must raise ValueError."
    finally:
        with open(FASTA, "wb") as f:
            f.write(original_fasta)
        with open(PDB, "wb") as f:
            f.write(original_pdb)

    distances, params = _expected(FASTA, PDB)
    _run_and_validate(distances, params, "original")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
