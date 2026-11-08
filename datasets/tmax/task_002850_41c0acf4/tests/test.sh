#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import ast
import subprocess
import pytest
import requests
import numpy as np
import matplotlib.image as mpimg
from scipy.io import wavfile
from scipy.stats import gaussian_kde


def _run_python(path, timeout=30):
    return subprocess.run(
        ["python3", path],
        cwd="/home/user",
        env={**os.environ, "MPLBACKEND": "Agg"},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def test_test_api_script_exists_valid_and_runs():
    script_path = "/home/user/test_api.py"
    assert os.path.isfile(script_path), f"Test script is missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Test script is not executable: {script_path}"

    with open(script_path, "r") as f:
        content = f.read()

    try:
        tree = ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"Test script {script_path} contains invalid Python syntax: {e}")

    # Ensure this is a substantive regression test for both required endpoints,
    # rather than an empty but syntactically valid file.
    constants = {n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
    assert any("/audio_peaks" in value for value in constants), "Test script does not query /audio_peaks"
    assert any("/mesh_density" in value for value in constants), "Test script does not query /mesh_density"

    request_gets = [
        n for n in ast.walk(tree)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "get"
    ]
    assert len(request_gets) >= 2, "Test script must issue GET requests to both endpoints"

    status_refs = [
        n for n in ast.walk(tree)
        if isinstance(n, ast.Attribute) and n.attr == "status_code"
    ]
    assert len(status_refs) >= 2, "Test script must check both HTTP status codes"

    assertions = [n for n in ast.walk(tree) if isinstance(n, ast.Assert)]
    assert assertions, "Test script contains no assertions"
    for key in ("peaks", "density"):
        assert any(
            any(isinstance(x, ast.Constant) and x.value == key for x in ast.walk(node.test))
            for node in assertions
        ), f"Test script does not assert that the '{key}' JSON key exists"

    result = _run_python(script_path)
    assert result.returncode == 0, (
        f"Regression test script failed when executed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def _read_valid_image(path):
    assert os.path.isfile(path), f"Visualization image is missing at {path}"
    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "Visualization is not a PNG file"
    image = np.asarray(mpimg.imread(path), dtype=float)
    assert image.ndim in (2, 3), "Visualization has an invalid pixel array"
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "Visualization is unreasonably small"
    rgb = image if image.ndim == 2 else image[..., :3]
    midpoint = rgb.shape[0] // 2
    assert np.std(rgb[:midpoint]) > 1e-3, "Top panel appears blank"
    assert np.std(rgb[midpoint:]) > 1e-3, "Bottom panel appears blank"
    return rgb.copy()


def _run_plot(script_path, image_path):
    if os.path.exists(image_path):
        os.remove(image_path)
    result = _run_python(script_path, timeout=60)
    assert result.returncode == 0, (
        f"Plot script failed when executed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return _read_valid_image(image_path)


def test_plot_data_script_executes_and_visualizes_both_inputs():
    script_path = "/home/user/plot_data.py"
    image_path = "/home/user/experiment_viz.png"
    audio_path = "/app/signal.wav"
    csv_path = "/home/user/samples.csv"

    assert os.path.isfile(script_path), f"Plot script is missing at {script_path}"
    with open(script_path, "r") as f:
        content = f.read()
    try:
        ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"Plot script {script_path} contains invalid Python syntax: {e}")

    with open(audio_path, "rb") as f:
        original_audio = f.read()
    with open(csv_path, "rb") as f:
        original_csv = f.read()

    restore_result = None
    try:
        baseline = _run_plot(script_path, image_path)

        sample_rate, signal = wavfile.read(audio_path)
        count = len(signal)
        t = np.arange(count) / float(sample_rate)
        changed_signal = (0.8 * np.sin(2 * np.pi * 1234 * t)).astype(np.float32)
        wavfile.write(audio_path, sample_rate, changed_signal)
        audio_changed = _run_plot(script_path, image_path)
        assert audio_changed.shape == baseline.shape, "Plot dimensions changed unexpectedly"

        # Restore audio, then alter only the coordinate samples.
        with open(audio_path, "wb") as f:
            f.write(original_audio)
        changed_samples = np.concatenate([
            np.linspace(5, 20, 100),
            np.linspace(80, 95, 100),
        ])
        np.savetxt(csv_path, changed_samples, fmt="%.4f")
        csv_changed = _run_plot(script_path, image_path)
        assert csv_changed.shape == baseline.shape, "Plot dimensions changed unexpectedly"

        split = baseline.shape[0] // 2
        audio_top_diff = np.mean(np.abs(audio_changed[:split] - baseline[:split]))
        audio_bottom_diff = np.mean(np.abs(audio_changed[split:] - baseline[split:]))
        csv_top_diff = np.mean(np.abs(csv_changed[:split] - baseline[:split]))
        csv_bottom_diff = np.mean(np.abs(csv_changed[split:] - baseline[split:]))

        assert audio_top_diff > 1e-5, "Changing the audio does not affect the top waveform panel"
        assert audio_top_diff > 2 * audio_bottom_diff, "Audio data is not plotted primarily in the top panel"
        assert csv_bottom_diff > 1e-5, "Changing the CSV does not affect the bottom density panel"
        assert csv_bottom_diff > 2 * csv_top_diff, "CSV density is not plotted primarily in the bottom panel"
    finally:
        with open(audio_path, "wb") as f:
            f.write(original_audio)
        with open(csv_path, "wb") as f:
            f.write(original_csv)
        if os.path.isfile(script_path):
            if os.path.exists(image_path):
                os.remove(image_path)
            restore_result = _run_python(script_path, timeout=60)

    assert restore_result is not None and restore_result.returncode == 0, "Plot script failed after restoring fixtures"
    _read_valid_image(image_path)


def test_experiment_viz_exists():
    image_path = "/home/user/experiment_viz.png"
    assert os.path.isfile(image_path), f"Visualization image is missing at {image_path}"


def test_audio_peaks_endpoint():
    url = "http://127.0.0.1:8080/audio_peaks"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON")

    assert "peaks" in data, "JSON response missing 'peaks' key"
    peaks = data["peaks"]
    assert isinstance(peaks, list), "'peaks' should be a list"
    assert len(peaks) == 3, f"Expected 3 peaks, got {len(peaks)}"

    expected_peaks = [300, 600, 900]
    for actual, expected in zip(sorted(peaks), expected_peaks):
        assert abs(actual - expected) <= 5, f"Peak {actual} is not within 5 Hz of expected {expected}"


def test_mesh_density_endpoint():
    csv_path = "/home/user/samples.csv"
    assert os.path.isfile(csv_path), f"Samples CSV is missing at {csv_path}"

    samples = np.loadtxt(csv_path)
    kde = gaussian_kde(samples, bw_method="scott")
    eval_points = np.array([10, 20, 30, 40, 50, 60, 70, 80, 90])
    expected_density = kde(eval_points)

    url = "http://127.0.0.1:8080/mesh_density"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON")

    assert "density" in data, "JSON response missing 'density' key"
    density = data["density"]
    assert isinstance(density, list), "'density' should be a list"
    assert len(density) == 9, f"Expected 9 density values, got {len(density)}"

    np.testing.assert_allclose(
        density,
        expected_density,
        rtol=1e-3,
        atol=1e-4,
        err_msg="Density values do not match expected KDE evaluation",
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
