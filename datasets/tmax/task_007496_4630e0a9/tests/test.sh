#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import runpy

import numpy as np
import scipy.optimize

SCRIPT_PATH = "/home/user/prepare_data.py"
OUTPUT_PATH = "/home/user/training_data.json"


def expected_signal(t):
    return (
        3 * np.sin(2 * np.pi * 1.5 * t)
        + 2 * np.cos(2 * np.pi * 3.0 * t)
        + 1.5 * np.sin(2 * np.pi * 5.0 * t)
    )


def test_script_exists():
    """Check that the prepare_data.py script exists."""
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."


def test_script_executes_required_pipeline():
    """Execute the script from a clean output state and observe required operations."""
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    original_minimize = scipy.optimize.minimize
    original_fft = np.fft.fft
    minimize_calls = []
    fft_inputs = []

    def tracked_minimize(fun, x0, *args, **kwargs):
        method = kwargs.get("method")
        if method is None and len(args) > 1:
            method = args[1]

        probes = np.array([0.123, 1.234, 8.0])
        observed = []
        for probe in probes:
            value = np.asarray(fun(np.array([probe]))).squeeze()
            observed.append(float(value))

        minimize_calls.append({
            "x0": np.asarray(x0, dtype=float).reshape(-1).copy(),
            "method": method,
            "probes": probes,
            "values": np.asarray(observed),
        })
        return original_minimize(fun, x0, *args, **kwargs)

    def tracked_fft(a, *args, **kwargs):
        fft_inputs.append(np.asarray(a).copy())
        return original_fft(a, *args, **kwargs)

    scipy.optimize.minimize = tracked_minimize
    np.fft.fft = tracked_fft
    old_cwd = os.getcwd()
    try:
        os.chdir("/home/user")
        runpy.run_path(SCRIPT_PATH, run_name="__main__")
    finally:
        os.chdir(old_cwd)
        scipy.optimize.minimize = original_minimize
        np.fft.fft = original_fft

    assert os.path.isfile(OUTPUT_PATH), \
        "Executing prepare_data.py did not create /home/user/training_data.json."

    valid_minimize_calls = []
    for call in minimize_calls:
        if (
            call["method"] == "Nelder-Mead"
            and call["x0"].size == 1
            and math.isclose(float(call["x0"][0]), 8.0, abs_tol=1e-12)
            and np.allclose(call["values"], expected_signal(call["probes"]), atol=1e-10)
        ):
            valid_minimize_calls.append(call)
    assert valid_minimize_calls, \
        "The script did not call scipy.optimize.minimize with the required signal, initial guess 8.0, and Nelder-Mead method."

    t = np.linspace(0, 10, 1000, endpoint=False)
    signal = expected_signal(t)
    expected_segments = np.split(signal, 4)
    assert len(fft_inputs) >= 4, "The script must call np.fft.fft for all four segments."
    for index, expected_segment in enumerate(expected_segments):
        assert any(
            actual.shape == (250,) and np.allclose(actual, expected_segment, atol=1e-10)
            for actual in fft_inputs
        ), f"np.fft.fft was not called with the expected data for segment {index}."


def test_output_json_exists_and_correct():
    """Check that training_data.json exists and contains the correct values."""
    output_path = "/home/user/training_data.json"
    assert os.path.exists(output_path), f"The output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"The path {output_path} is not a file."

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {output_path} does not contain valid JSON."

    # Check structure
    assert "local_minimum" in data, "Key 'local_minimum' missing in JSON."
    assert "segments_power" in data, "Key 'segments_power' missing in JSON."

    local_min = data["local_minimum"]
    assert "t" in local_min, "Key 't' missing in 'local_minimum'."
    assert "f_t" in local_min, "Key 'f_t' missing in 'local_minimum'."

    segments = data["segments_power"]
    assert isinstance(segments, list), "'segments_power' must be a list."
    assert len(segments) == 4, "'segments_power' must contain exactly 4 segments."

    # Verify values with a small tolerance due to rounding
    expected_t = 8.1678
    expected_f_t = -4.0156
    expected_power = 600.6726

    assert math.isclose(local_min["t"], expected_t, abs_tol=0.001), \
        f"Expected local_minimum.t to be near {expected_t}, got {local_min['t']}."

    assert math.isclose(local_min["f_t"], expected_f_t, abs_tol=0.001), \
        f"Expected local_minimum.f_t to be near {expected_f_t}, got {local_min['f_t']}."

    for i, seg in enumerate(segments):
        assert "segment" in seg, f"Key 'segment' missing in segments_power[{i}]."
        assert "power" in seg, f"Key 'power' missing in segments_power[{i}]."
        assert seg["segment"] == i, f"Expected segment index {i}, got {seg['segment']}."
        assert math.isclose(seg["power"], expected_power, abs_tol=0.001), \
            f"Expected power for segment {i} to be near {expected_power}, got {seg['power']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
