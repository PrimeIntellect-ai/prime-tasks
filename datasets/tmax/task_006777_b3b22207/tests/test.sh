#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'HOOK_EOF' > /tmp/sitecustomize.py
import builtins
import hashlib
import json
import os
import time

import numpy as np

FFT_MARKER = "/tmp/verifier_fft_calls.jsonl"
PLOT_MARKER = "/tmp/verifier_plot_calls.jsonl"

_original_fft = np.fft.fft

def _digest(values):
    arr = np.asarray(values, dtype=np.float64)
    return hashlib.sha256(np.ascontiguousarray(arr).tobytes()).hexdigest()

def _checked_fft(a, *args, **kwargs):
    arr = np.asarray(a)
    # Make a genuine timing measurement distinguishable from a fabricated tiny value.
    start = time.perf_counter()
    while time.perf_counter() - start < 0.08:
        pass
    try:
        record = {
            "shape": list(arr.shape),
            "digest": _digest(arr),
        }
        with open(FFT_MARKER, "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception:
        pass
    return _original_fft(a, *args, **kwargs)

np.fft.fft = _checked_fft

_original_import = builtins.__import__
_plot_patched = False
_patching = False

def _record_plot(kind, x, y):
    try:
        xa = np.asarray(x, dtype=np.float64).reshape(-1)
        ya = np.asarray(y, dtype=np.float64).reshape(-1)
        if xa.size > 100000 or ya.size > 100000:
            return
        record = {
            "kind": kind,
            "x": xa.tolist(),
            "y": ya.tolist(),
        }
        with open(PLOT_MARKER, "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception:
        pass

def _maybe_patch_plotting():
    global _plot_patched, _patching
    if _plot_patched or _patching:
        return
    import sys
    plt = sys.modules.get("matplotlib.pyplot")
    if plt is None or not hasattr(plt, "plot"):
        return
    _patching = True
    try:
        from matplotlib.axes import Axes
        original_plot = Axes.plot
        original_scatter = Axes.scatter

        def checked_plot(self, *args, **kwargs):
            numeric = [v for v in args if not isinstance(v, str)]
            if len(numeric) == 1:
                y = np.asarray(numeric[0]).reshape(-1)
                _record_plot("plot", np.arange(y.size), y)
            elif len(numeric) >= 2:
                _record_plot("plot", numeric[0], numeric[1])
            return original_plot(self, *args, **kwargs)

        def checked_scatter(self, x, y, *args, **kwargs):
            _record_plot("scatter", x, y)
            return original_scatter(self, x, y, *args, **kwargs)

        Axes.plot = checked_plot
        Axes.scatter = checked_scatter
        _plot_patched = True
    finally:
        _patching = False

def _checked_import(name, globals=None, locals=None, fromlist=(), level=0):
    result = _original_import(name, globals, locals, fromlist, level)
    try:
        _maybe_patch_plotting()
    except Exception:
        pass
    return result

builtins.__import__ = _checked_import
HOOK_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest

SCRIPT = "/home/user/process_waves.py"
RAW = "/home/user/raw_waves.csv"
OUTPUTS = [
    "/home/user/cleaned_waves.csv",
    "/home/user/benchmark.txt",
    "/home/user/accuracy.json",
    "/home/user/spectrum.png",
]
FFT_MARKER = "/tmp/verifier_fft_calls.jsonl"
PLOT_MARKER = "/tmp/verifier_plot_calls.jsonl"


def digest(values):
    arr = np.asarray(values, dtype=np.float64)
    return hashlib.sha256(np.ascontiguousarray(arr).tobytes()).hexdigest()


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist or is not a regular file."
    assert os.path.getsize(SCRIPT) > 0, f"File {SCRIPT} is empty."
    assert os.path.isfile(RAW), f"Raw input {RAW} is missing."

    for path in OUTPUTS:
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        elif os.path.lexists(path):
            os.unlink(path)
    for marker in (FFT_MARKER, PLOT_MARKER):
        if os.path.lexists(marker):
            os.unlink(marker)

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp" + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env.pop("DISPLAY", None)
    try:
        result = subprocess.run(
            [sys.executable, SCRIPT],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("process_waves.py did not finish within 30 seconds.")
    assert result.returncode == 0, (
        f"process_waves.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def expected_cleaned():
    return pd.read_csv(RAW).dropna(subset=["amplitude"])


def test_cleaned_waves_csv():
    path = "/home/user/cleaned_waves.csv"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        lines = f.readlines()

    assert len(lines) > 0, f"File {path} is empty."
    # The header is 1 line, plus 997 data rows = 998 lines
    assert len(lines) == 998, f"Expected exactly 998 lines (header + 997 rows) in {path}, but found {len(lines)}."

    actual = pd.read_csv(path)
    expected = expected_cleaned()
    assert list(actual.columns) == list(expected.columns), "The cleaned CSV must keep the original header and column order."
    pd.testing.assert_frame_equal(
        actual.reset_index(drop=True),
        expected.reset_index(drop=True),
        check_dtype=False,
        rtol=1e-12,
        atol=1e-12,
    )
    assert not actual["amplitude"].isna().any(), "The cleaned amplitude column still contains NaN values."


def test_fft_was_computed_on_cleaned_amplitudes():
    assert os.path.isfile(FFT_MARKER), "process_waves.py never called numpy.fft.fft."
    expected = expected_cleaned()["amplitude"].to_numpy(dtype=np.float64)
    expected_digest = digest(expected)
    with open(FFT_MARKER) as f:
        calls = [json.loads(line) for line in f if line.strip()]
    assert any(call.get("shape") == [len(expected)] and call.get("digest") == expected_digest for call in calls), (
        "numpy.fft.fft was not called with the cleaned amplitude array."
    )


def test_benchmark_txt():
    path = "/home/user/benchmark.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {path} could not be parsed as a float. Content: '{content}'")

    assert val > 0.0, f"Benchmark time in {path} should be a positive float, got {val}."
    assert math.isfinite(val), f"Benchmark time in {path} must be finite, got {val}."
    assert val >= 0.06, "The reported benchmark did not encompass the instrumented numpy.fft.fft call."
    assert val < 10.0, f"Benchmark time is implausibly large: {val}."


def test_accuracy_json():
    path = "/home/user/accuracy.json"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert "accurate" in data, f"'accurate' key missing in {path}."
    assert "parseval_diff" in data, f"'parseval_diff' key missing in {path}."

    assert data["accurate"] is True, f"Expected 'accurate' to be True, got {data['accurate']}."
    assert isinstance(data["parseval_diff"], (float, int)), f"'parseval_diff' should be a number."
    assert data["parseval_diff"] < 1e-5, f"Expected 'parseval_diff' to be < 1e-5, got {data['parseval_diff']}."

    assert set(data) == {"parseval_diff", "accurate"}, "accuracy.json contains unexpected keys."
    amplitudes = expected_cleaned()["amplitude"].to_numpy(dtype=np.float64)
    transformed = np.fft.fft(amplitudes)
    expected_diff = abs(
        np.sum(np.square(amplitudes))
        - np.sum(np.square(np.abs(transformed))) / len(amplitudes)
    )
    reported = float(data["parseval_diff"])
    assert math.isfinite(reported) and reported >= 0.0, "parseval_diff must be a finite non-negative number."
    assert math.isclose(reported, float(expected_diff), rel_tol=1e-7, abs_tol=1e-10), (
        f"parseval_diff was not computed from the cleaned data: expected {expected_diff}, got {reported}."
    )
    assert data["accurate"] is (expected_diff < 1e-5), "The accurate flag does not match the computed difference."


def test_spectrum_data_was_plotted():
    assert os.path.isfile(PLOT_MARKER), "No line or scatter spectrum data was plotted."
    amplitudes = expected_cleaned()["amplitude"].to_numpy(dtype=np.float64)
    expected_y = np.abs(np.fft.fft(amplitudes))
    expected_x = np.arange(len(expected_y), dtype=np.float64)
    matches = False
    with open(PLOT_MARKER) as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            x = np.asarray(record.get("x", []), dtype=np.float64)
            y = np.asarray(record.get("y", []), dtype=np.float64)
            if x.shape == expected_x.shape and y.shape == expected_y.shape:
                if np.allclose(x, expected_x, rtol=0, atol=1e-12) and np.allclose(y, expected_y, rtol=1e-10, atol=1e-10):
                    matches = True
                    break
    assert matches, "The plotted data is not the absolute FFT values against their indices."


def test_spectrum_png():
    path = "/home/user/spectrum.png"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'rb') as f:
        header = f.read(8)

    assert header == b'\x89PNG\r\n\x1a\n', f"File {path} is not a valid PNG image."

    size = os.path.getsize(path)
    assert size > 3000, f"File {path} is suspiciously small ({size} bytes), likely a blank or broken plot."

    image = mpimg.imread(path)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, "The PNG has invalid dimensions."
    pixels = image[..., :3] if image.ndim == 3 else image
    assert np.isfinite(pixels).all(), "The PNG contains invalid pixel values."
    assert float(np.std(pixels)) > 0.01, "The spectrum PNG is visually blank or nearly uniform."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
