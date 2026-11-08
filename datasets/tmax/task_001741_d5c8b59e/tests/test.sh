#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.util
import json
import os
import subprocess
import sys
import uuid
import warnings

import numpy as np
import pandas as pd
import pytest
from scipy import sparse
from scipy.sparse.linalg import spsolve

SCRIPT_PATH = "/home/user/sanitize_data.py"
LOG_PATH = "/home/user/classification.log"
SOURCE_BASELINE = "/app/spectro-tools-0.4.2/spectro_tools/baseline.py"


def reference_remove_baseline(y, lam=1e5, p=0.01, itermax=10):
    y = np.asarray(y)
    length = len(y)
    dmat = sparse.diags([1, -2, 1], [0, -1, -2], shape=(length, length - 2))
    dmat = lam * dmat.dot(dmat.transpose())
    weights = np.ones(length)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        for _ in range(itermax):
            wmat = sparse.diags(weights, 0, shape=(length, length))
            baseline = spsolve(wmat + dmat, weights * y)
            weights = p * (y > baseline) + (1 - p) * (y < baseline)
    return y - baseline


def assert_baseline_matches_reference(function):
    cases = [
        (np.array([1.0, 2.2, 1.7, 4.4, 3.1]), 1e5, 0.01, 10),
        (np.sin(np.linspace(0, 4, 31)) + np.linspace(2, 5, 31), 2500.0, 0.08, 7),
        (np.array([3.0, 1.0, 4.0, 1.5, 5.0, 2.0, 6.0]), 700.0, 0.2, 4),
    ]
    for signal, lam, p, iterations in cases:
        expected = reference_remove_baseline(signal, lam=lam, p=p, itermax=iterations)
        actual = function(signal.copy(), lam=lam, p=p, itermax=iterations)
        assert isinstance(actual, np.ndarray), "remove_baseline should return a numpy array."
        assert actual.shape == signal.shape
        np.testing.assert_allclose(actual, expected, rtol=1e-9, atol=1e-9, equal_nan=True)


def test_spectro_tools_installed_and_fixed():
    """Verify that both the installed package and repaired vendored source work correctly."""
    try:
        import spectro_tools.baseline
    except ImportError as exc:
        pytest.fail(f"spectro_tools is not installed properly or cannot be imported: {exc}")

    intensity = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    try:
        corrected = spectro_tools.baseline.remove_baseline(intensity)
        assert isinstance(corrected, np.ndarray), "remove_baseline should return a numpy array."
    except NameError as exc:
        pytest.fail(f"The bug in spectro_tools.baseline was not fixed (NameError encountered): {exc}")
    except Exception as exc:
        pytest.fail(f"An unexpected error occurred when calling remove_baseline: {exc}")

    assert_baseline_matches_reference(spectro_tools.baseline.remove_baseline)

    assert os.path.isfile(SOURCE_BASELINE), f"Vendored source file {SOURCE_BASELINE} is missing."
    spec = importlib.util.spec_from_file_location("submitted_source_baseline", SOURCE_BASELINE)
    source_module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(source_module)
        assert_baseline_matches_reference(source_module.remove_baseline)
    except NameError as exc:
        pytest.fail(f"The vendored baseline.py source still has the missing-reference bug: {exc}")


def run_script_and_parse_log(input_dir, env=None):
    """Run the submitted script and parse its output log."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, "--input-dir", input_dir],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} was not created by the script."

    classifications = {}
    with open(LOG_PATH, "r") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            if ": " in line:
                filename, status = line.split(": ", 1)
                classifications[filename] = status
    return classifications


def test_clean_corpus_accepted():
    clean_dir = "/app/data/clean/"
    assert os.path.isdir(clean_dir), f"Clean data directory {clean_dir} is missing."
    csv_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    assert len(csv_files) > 0, f"No CSV files found in {clean_dir}."
    classifications = run_script_and_parse_log(clean_dir)

    rejected = []
    missing = []
    for file_path in csv_files:
        filename = os.path.basename(file_path)
        if filename not in classifications:
            missing.append(filename)
        elif classifications[filename] != "ACCEPT":
            rejected.append(filename)

    errors = []
    if rejected:
        errors.append(f"{len(rejected)} of {len(csv_files)} clean modified (rejected): {', '.join(rejected[:5])}")
    if missing:
        errors.append(f"{len(missing)} files missing from log: {', '.join(missing[:5])}")
    if errors:
        pytest.fail("; ".join(errors))


def test_evil_corpus_rejected():
    evil_dir = "/app/data/evil/"
    assert os.path.isdir(evil_dir), f"Evil data directory {evil_dir} is missing."
    csv_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    assert len(csv_files) > 0, f"No CSV files found in {evil_dir}."
    classifications = run_script_and_parse_log(evil_dir)

    accepted = []
    missing = []
    for file_path in csv_files:
        filename = os.path.basename(file_path)
        if filename not in classifications:
            missing.append(filename)
        elif classifications[filename] != "REJECT":
            accepted.append(filename)

    errors = []
    if accepted:
        errors.append(f"{len(accepted)} of {len(csv_files)} evil bypassed (accepted): {', '.join(accepted[:5])}")
    if missing:
        errors.append(f"{len(missing)} files missing from log: {', '.join(missing[:5])}")
    if errors:
        pytest.fail("; ".join(errors))


def make_hidden_mixed_corpus(directory):
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    expected = {}
    intensities = {}

    for index in range(12):
        wavelength = 400.0 + np.cumsum(rng.uniform(1.2, 3.2, size=257))
        center = rng.uniform(wavelength[70], wavelength[190])
        width = rng.uniform(35.0, 75.0)
        intensity = (
            30.0
            + 0.003 * (wavelength - wavelength[0])
            + rng.uniform(10.0, 30.0) * np.exp(-((wavelength - center) / width) ** 2)
            + rng.normal(0.0, 0.01, size=wavelength.size)
        )

        mode = index % 3
        if mode == 1:
            spike = int(rng.integers(40, 215))
            intensity[spike] += 5000.0
            intensity[spike + 1] -= 5000.0
        elif mode == 2:
            intensity[int(rng.integers(40, 215))] = np.nan

        filename = f"{uuid.uuid4().hex}.csv"
        path = os.path.join(directory, filename)
        pd.DataFrame({"wavelength": wavelength, "intensity": intensity}).to_csv(path, index=False)

        loaded = pd.read_csv(path)
        x = loaded["wavelength"].to_numpy(dtype=float)
        y = loaded["intensity"].to_numpy(dtype=float)
        corrected = reference_remove_baseline(y)
        if np.any(~np.isfinite(corrected)):
            status = "REJECT"
        else:
            derivative = np.gradient(corrected, x)
            status = "REJECT" if np.any(~np.isfinite(derivative)) or np.any(np.abs(derivative) > 50.0) else "ACCEPT"
        expected[filename] = status
        intensities[filename] = y

    assert "ACCEPT" in expected.values() and "REJECT" in expected.values()
    return expected, intensities


def make_call_tracer(hook_dir, trace_path):
    sitecustomize = os.path.join(hook_dir, "sitecustomize.py")
    with open(sitecustomize, "w") as handle:
        handle.write(r'''import json
import os
import numpy as np
import spectro_tools
import spectro_tools.baseline as _baseline

_original = _baseline.remove_baseline
_trace = os.environ["SPECTRO_CALL_TRACE"]

def _traced_remove_baseline(y, *args, **kwargs):
    array = np.asarray(y, dtype=float)
    with open(_trace, "a") as stream:
        stream.write(json.dumps({"shape": list(array.shape), "values": array.tolist()}) + "\\n")
    return _original(y, *args, **kwargs)

_baseline.remove_baseline = _traced_remove_baseline
spectro_tools.remove_baseline = _traced_remove_baseline
''')


def test_hidden_mixed_corpus_and_required_baseline_calls(tmp_path):
    corpus = tmp_path / uuid.uuid4().hex
    corpus.mkdir()
    expected, intensities = make_hidden_mixed_corpus(str(corpus))

    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    trace_path = tmp_path / "baseline_calls.jsonl"
    make_call_tracer(str(hook_dir), str(trace_path))

    env = os.environ.copy()
    env["SPECTRO_CALL_TRACE"] = str(trace_path)
    env["PYTHONPATH"] = str(hook_dir) + os.pathsep + env.get("PYTHONPATH", "")
    run_script_and_parse_log(str(corpus), env=env)

    with open(LOG_PATH, "r") as handle:
        lines = [line.rstrip("\n") for line in handle if line.rstrip("\n")]
    expected_lines = {f"{filename}: {status}" for filename, status in expected.items()}
    assert len(lines) == len(expected), "classification.log must contain exactly one result per CSV file."
    assert set(lines) == expected_lines, "Hidden mixed corpus was not classified according to the required rules."

    assert trace_path.exists(), "sanitize_data.py did not call spectro_tools.baseline.remove_baseline."
    calls = []
    with open(trace_path, "r") as handle:
        for line in handle:
            record = json.loads(line)
            calls.append(np.asarray(record["values"], dtype=float))

    for filename, expected_intensity in intensities.items():
        assert any(
            call.shape == expected_intensity.shape
            and np.allclose(call, expected_intensity, rtol=1e-12, atol=1e-12, equal_nan=True)
            for call in calls
        ), f"remove_baseline was not called with the intensity data from {filename}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
