#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.metadata
import os
import runpy

import numpy as np
import pytest
from scipy.signal import savgol_filter
from scipy.stats import wasserstein_distance


def read_output():
    output_path = "/home/user/mean_distance.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} was not created."
    with open(output_path, "r") as f:
        content = f.read().strip()
    try:
        return float(content)
    except ValueError:
        pytest.fail(f"Content of {output_path} is not a valid float: {content}")


def expected_from_smoothed(smoothed_rows, theoretical):
    distances = []
    for smoothed, target in zip(smoothed_rows, theoretical):
        smoothed_norm = smoothed / np.sum(smoothed)
        target_norm = target / np.sum(target)
        distances.append(wasserstein_distance(smoothed_norm, target_norm))
    return float(np.mean(distances))


def test_bug_fixed():
    """Test that the deliberate bug in core.py has been fixed."""
    core_py_path = "/app/spec_smooth/spec_smooth/core.py"
    assert os.path.isfile(core_py_path), f"{core_py_path} is missing."

    with open(core_py_path, "r") as f:
        content = f.read()

    assert "import nump as np" not in content, "The deliberate bug 'import nump as np' is still present in core.py."
    assert "import numpy as np" in content, "The import statement was not correctly fixed to 'import numpy as np'."


def test_package_is_installed_and_functional():
    """Require an installed, importable spec_smooth distribution with a working API."""
    try:
        importlib.metadata.distribution("spec_smooth")
    except importlib.metadata.PackageNotFoundError:
        pytest.fail("spec_smooth was not installed into the Python environment.")

    import spec_smooth

    assert callable(getattr(spec_smooth, "smooth", None)), "spec_smooth.smooth is unavailable."
    signal = np.linspace(0.0, 1.0, 31) ** 2
    actual = np.asarray(spec_smooth.smooth(signal, window_length=15, polyorder=3))
    expected = savgol_filter(signal, window_length=15, polyorder=3)
    assert np.allclose(actual, expected), "The installed spec_smooth.smooth function is not functional."


def test_processing_script_created_and_used():
    """Execute the submitted pipeline and ensure its result depends on spec_smooth.smooth."""
    import spec_smooth

    scripts = []
    for path in glob.glob("/home/user/**/*.py", recursive=True):
        relative_parts = os.path.relpath(path, "/home/user").split(os.sep)
        if any(part.startswith(".") for part in relative_parts):
            continue
        try:
            with open(path, "r") as f:
                source = f.read()
        except (OSError, UnicodeDecodeError):
            continue
        if "noisy_spectra.npy" in source and "theoretical_spectra.npy" in source and "spec_smooth" in source:
            scripts.append(path)

    scripts.sort(key=lambda p: (os.path.basename(p) != "process_spectra.py", p))
    assert scripts, "No Python processing script loading both spectra arrays and using spec_smooth was found."

    noisy = np.load("/app/data/noisy_spectra.npy")
    theoretical = np.load("/app/data/theoretical_spectra.npy")
    original_smooth = spec_smooth.smooth
    output_path = "/home/user/mean_distance.txt"
    selected = None
    failures = []

    for script in scripts:
        calls = []

        def instrumented(signal, window_length=15, polyorder=3):
            result = np.asarray(original_smooth(signal, window_length=window_length, polyorder=polyorder))
            altered = result + 0.731
            calls.append((np.asarray(signal).copy(), window_length, polyorder, altered.copy()))
            return altered

        spec_smooth.smooth = instrumented
        try:
            if os.path.exists(output_path):
                os.remove(output_path)
            runpy.run_path(script, run_name="__main__")
            assert len(calls) == noisy.shape[0], "The script did not call spec_smooth.smooth once per noisy spectrum."
            for i, (signal, window_length, polyorder, _) in enumerate(calls):
                assert window_length == 15 and polyorder == 3, "The required smoothing parameters were not used."
                assert np.array_equal(signal, noisy[i]), "The script did not smooth the noisy spectra in order."

            altered_expected = expected_from_smoothed([call[3] for call in calls], theoretical)
            altered_value = read_output()
            assert np.isclose(altered_value, altered_expected, rtol=1e-6, atol=1e-8), \
                "The processing script's output does not depend on values returned by spec_smooth.smooth."
            selected = script
            break
        except BaseException as exc:
            failures.append(f"{script}: {exc}")
        finally:
            spec_smooth.smooth = original_smooth

    assert selected is not None, "No submitted processing script completed the required workflow: " + "; ".join(failures)

    # Run the accepted script normally so subsequent assertions inspect its real output.
    normal_calls = []

    def recording_smooth(signal, window_length=15, polyorder=3):
        result = original_smooth(signal, window_length=window_length, polyorder=polyorder)
        normal_calls.append((np.asarray(signal).copy(), window_length, polyorder))
        return result

    spec_smooth.smooth = recording_smooth
    try:
        if os.path.exists(output_path):
            os.remove(output_path)
        runpy.run_path(selected, run_name="__main__")
    finally:
        spec_smooth.smooth = original_smooth

    assert len(normal_calls) == noisy.shape[0], "The normal pipeline run did not smooth every spectrum."


def test_output_file_exists():
    """Test that the output file was created."""
    output_path = "/home/user/mean_distance.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} was not created."


def test_metric_threshold():
    """Test that the computed mean Wasserstein distance meets the threshold."""
    val = read_output()
    threshold = 0.005
    assert val <= threshold, f"Mean Wasserstein distance {val} is greater than threshold {threshold}."


def test_actual_computation_correctness():
    """Test that the value in the output file matches the actual expected computation."""
    theoretical_path = "/app/data/theoretical_spectra.npy"
    noisy_path = "/app/data/noisy_spectra.npy"

    assert os.path.isfile(theoretical_path), f"{theoretical_path} is missing."
    assert os.path.isfile(noisy_path), f"{noisy_path} is missing."

    theoretical = np.load(theoretical_path)
    noisy = np.load(noisy_path)
    distances = []

    for i in range(noisy.shape[0]):
        smoothed = savgol_filter(noisy[i], window_length=15, polyorder=3)
        smoothed_norm = smoothed / np.sum(smoothed)
        theoretical_norm = theoretical[i] / np.sum(theoretical[i])
        distances.append(wasserstein_distance(smoothed_norm, theoretical_norm))

    expected_mean_distance = np.mean(distances)
    val = read_output()
    assert np.isclose(val, expected_mean_distance, rtol=1e-3, atol=1e-5), \
        f"Submitted distance {val} does not match the expected computed distance {expected_mean_distance}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
