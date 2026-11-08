#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_instrumentation
cat << 'SITE_EOF' > /tmp/verifier_instrumentation/sitecustomize.py
import json
import os
import numpy as np

try:
    from matplotlib.figure import Figure

    _original_savefig = Figure.savefig

    def _recording_savefig(self, *args, **kwargs):
        metadata_path = os.environ.get("VERIFIER_PLOT_METADATA")
        if metadata_path:
            axes = []
            for ax in self.axes:
                lines = []
                for line in ax.get_lines():
                    try:
                        x = np.asarray(line.get_xdata(), dtype=float)
                        y = np.asarray(line.get_ydata(), dtype=float)
                        lines.append({"x": x.tolist(), "y": y.tolist()})
                    except Exception:
                        pass
                axes.append({
                    "position": list(ax.get_position().bounds),
                    "xlim": list(ax.get_xlim()),
                    "lines": lines,
                })
            with open(metadata_path, "w") as f:
                json.dump({"axes": axes}, f)
        return _original_savefig(self, *args, **kwargs)

    Figure.savefig = _recording_savefig
except Exception:
    pass
SITE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pytest
from scipy.signal import find_peaks

SCRIPT_PATH = "/home/user/process_signal.py"
JSON_PATH = "/home/user/spectral_results.json"
PLOT_PATH = "/home/user/spectroscopy_analysis.png"
METADATA_PATH = "/tmp/verifier_plot_metadata.json"


def reference_results():
    fs = 1000
    t = np.arange(1000, dtype=float) / fs
    clean = (
        1.0 * np.exp(-t / 0.1) * np.cos(2 * np.pi * 50 * t)
        + 0.8 * np.exp(-t / 0.2) * np.cos(2 * np.pi * 120 * t)
        + 0.5 * np.exp(-t / 0.05) * np.cos(2 * np.pi * 200 * t)
    )
    np.random.seed(42)
    noisy = clean + np.random.normal(0.0, 0.05, t.size)

    frequencies = np.fft.rfftfreq(t.size, d=1.0 / fs)
    magnitude = np.abs(np.fft.rfft(noisy)) / t.size
    magnitude[1:-1] *= 2.0

    candidates, _ = find_peaks(magnitude)
    strongest = candidates[np.argsort(magnitude[candidates])[-3:]]
    detected = sorted(float(frequencies[i]) for i in strongest)
    max_frequency = float(frequencies[int(np.argmax(magnitude))])
    return t, noisy, frequencies, magnitude, detected, max_frequency


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_PATH), f"Script file {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    for path in (JSON_PATH, PLOT_PATH, METADATA_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    env["VERIFIER_PLOT_METADATA"] = METADATA_PATH
    env["PYTHONPATH"] = "/tmp/verifier_instrumentation" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"process_signal.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_plot_exists():
    """Verify that the generated plot exists."""
    plot_path = "/home/user/spectroscopy_analysis.png"
    assert os.path.exists(plot_path), f"Plot file {plot_path} does not exist."
    assert os.path.isfile(plot_path), f"{plot_path} is not a file."
    assert os.path.getsize(plot_path) > 0, f"Plot file {plot_path} is empty."


def test_json_results():
    """Verify that the JSON results file exists and contains the correct data."""
    json_path = "/home/user/spectral_results.json"
    assert os.path.exists(json_path), f"JSON file {json_path} does not exist."
    assert os.path.isfile(json_path), f"{json_path} is not a file."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert "detected_frequencies" in data, "Key 'detected_frequencies' missing in JSON."
    assert "max_amplitude_frequency" in data, "Key 'max_amplitude_frequency' missing in JSON."

    detected = data["detected_frequencies"]
    assert isinstance(detected, list), "'detected_frequencies' must be a list."
    assert len(detected) == 3, f"Expected 3 detected frequencies, got {len(detected)}."

    # Sort just in case, though the prompt requires them to be sorted.
    detected_sorted = sorted(detected)
    expected_frequencies = [50.0, 120.0, 200.0]

    for expected, actual in zip(expected_frequencies, detected_sorted):
        assert abs(expected - actual) < 1.0, f"Expected detected frequency near {expected}, got {actual}."

    max_freq = data["max_amplitude_frequency"]
    assert abs(120.0 - max_freq) < 1.0, f"Expected max amplitude frequency near 120.0, got {max_freq}."

    _, _, _, _, independently_detected, independently_max = reference_results()
    assert set(data.keys()) == {"detected_frequencies", "max_amplitude_frequency"}, "JSON schema has unexpected keys."
    assert detected == sorted(detected), "Detected frequencies must be sorted in ascending order."
    assert np.allclose(detected, independently_detected, rtol=0, atol=1e-9), (
        f"Detected frequencies do not match the FFT-derived peaks: {independently_detected}."
    )
    assert abs(float(max_freq) - independently_max) < 1e-9, (
        f"Maximum-amplitude frequency should be {independently_max}."
    )


def test_script_exists():
    """Verify that the Python script was created."""
    script_path = "/home/user/process_signal.py"
    assert os.path.exists(script_path), f"Script file {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_required_libraries_and_fft_are_used():
    with open(SCRIPT_PATH, "r") as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    aliases_by_root = {"numpy": set(), "scipy": set(), "matplotlib": set()}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                root = item.name.split(".")[0]
                if root in aliases_by_root:
                    aliases_by_root[root].add(item.asname or root)
        elif isinstance(node, ast.ImportFrom) and node.module:
            root = node.module.split(".")[0]
            if root in aliases_by_root:
                for item in node.names:
                    aliases_by_root[root].add(item.asname or item.name)

    loaded_names = {
        node.id for node in ast.walk(tree)
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load)
    }
    for library, aliases in aliases_by_root.items():
        assert aliases and aliases.intersection(loaded_names), f"The script must import and use {library}."

    fft_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                name = node.func.id
            elif isinstance(node.func, ast.Attribute):
                name = node.func.attr
            else:
                name = ""
            if "fft" in name.lower():
                fft_calls.append(node)
    assert fft_calls, "The script must compute the spectrum using an FFT function."


def _has_matching_line(axis, expected_x, expected_y):
    for line in axis.get("lines", []):
        x = np.asarray(line.get("x", []), dtype=float)
        y = np.asarray(line.get("y", []), dtype=float)
        if x.shape == expected_x.shape and y.shape == expected_y.shape:
            if np.allclose(x, expected_x, rtol=0, atol=1e-12) and np.allclose(y, expected_y, rtol=1e-8, atol=1e-10):
                return True
    return False


def test_plot_is_valid_and_contains_required_data():
    image = mpimg.imread(PLOT_PATH)
    assert image.ndim in (2, 3), "The plot is not a readable PNG image."
    assert image.shape[0] >= 300 and image.shape[1] >= 300, "The plot is too small to contain the requested subplots."
    assert float(np.std(image)) > 0.01, "The plot image appears blank."

    assert os.path.isfile(METADATA_PATH), "The script did not save a Matplotlib figure."
    with open(METADATA_PATH, "r") as f:
        metadata = json.load(f)
    axes = metadata.get("axes", [])
    assert len(axes) == 2, f"Expected exactly two subplots, found {len(axes)}."

    # Higher y-position is the top subplot.
    axes = sorted(axes, key=lambda axis: axis["position"][1], reverse=True)
    top, bottom = axes
    assert top["position"][1] > bottom["position"][1], "Subplots must be arranged vertically."

    t, noisy, frequencies, magnitude, _, _ = reference_results()
    assert _has_matching_line(top, t, noisy), "Top subplot does not contain the required seeded noisy FID signal."
    assert _has_matching_line(bottom, frequencies, magnitude), "Bottom subplot does not contain the correctly normalized one-sided FFT spectrum."
    assert bottom["xlim"][0] <= 0.0 + 1e-6 and bottom["xlim"][1] >= 500.0 - 1e-6, "Spectrum subplot must display 0 through 500 Hz."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
