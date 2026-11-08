#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import re
import ctypes
import random
import shutil
import subprocess
import tempfile
from pathlib import Path

import cv2
import numpy as np
import pytest


def test_fast_mse_compiled():
    path = "/home/user/src/fast_mse.so"
    assert os.path.isfile(path), f"Compiled shared library {path} is missing."

    # Ensure this is a loadable shared library exporting a working compute_mse,
    # rather than merely a file with the expected name.
    try:
        lib = ctypes.CDLL(path)
        fn = lib.compute_mse
    except (OSError, AttributeError) as exc:
        pytest.fail(f"{path} is not a loadable library exporting compute_mse: {exc}")

    fn.argtypes = [
        np.ctypeslib.ndpointer(dtype=np.float64, ndim=1, flags="C_CONTIGUOUS"),
        np.ctypeslib.ndpointer(dtype=np.float64, ndim=1, flags="C_CONTIGUOUS"),
        ctypes.c_int,
    ]
    fn.restype = ctypes.c_double

    rng = np.random.default_rng()
    for length in (1, 7, 31, 103):
        a = np.ascontiguousarray(rng.normal(size=length), dtype=np.float64)
        b = np.ascontiguousarray(rng.normal(size=length), dtype=np.float64)
        expected = float(np.mean((a - b) ** 2))
        actual = float(fn(a, b, length))
        assert math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"compute_mse returned {actual}, expected {expected}"
        )


def _run_and_check_filter(script_path, directory, expected):
    result = subprocess.run(
        ["python3", script_path, directory],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Script failed on {directory}: {result.stderr}"

    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == len(expected), (
        f"Expected exactly one output line for each of {len(expected)} CSV files, "
        f"but got {len(lines)} lines: {lines[:10]}"
    )

    found = {}
    for line in lines:
        match = re.fullmatch(r"(.+): (CLEAN|EVIL)", line)
        assert match, f"Invalid output line: {line!r}"
        filename, label = match.groups()
        assert filename not in found, f"Duplicate output for {filename}"
        found[filename] = label

    assert set(found) == set(expected), (
        f"Output filenames differ from corpus files; missing={set(expected)-set(found)}, "
        f"extra={set(found)-set(expected)}"
    )
    for filename, label in expected.items():
        assert found[filename] == label, (
            f"{filename} was labeled {found[filename]}, expected {label}"
        )


def _write_trajectory(path, evil, rng):
    x = rng.uniform(80.0, 120.0)
    y = rng.uniform(80.0, 120.0)
    glitch_frame = rng.randint(5, 15)
    glitch_axis = rng.choice((0, 1))
    glitch_sign = rng.choice((-1.0, 1.0))
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["x", "y"])
        for frame in range(20):
            if evil and frame == glitch_frame:
                if glitch_axis == 0:
                    x += glitch_sign * rng.uniform(55.0, 75.0)
                else:
                    y += glitch_sign * rng.uniform(55.0, 75.0)
            else:
                x += rng.uniform(-5.0, 5.0)
                y += rng.uniform(-5.0, 5.0)
            writer.writerow([x, y])


def test_glitch_filter():
    script_path = "/home/user/glitch_filter.py"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    # Preserve the original hidden-corpus assertions, while requiring exactly
    # one correctly named line for every input file.
    clean_dir = "/app/corpus_hidden_eval/clean/"
    if not os.path.isdir(clean_dir):
        clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus_hidden_eval/evil/"
    if not os.path.isdir(evil_dir):
        evil_dir = "/app/corpus/evil/"

    clean_files = sorted(f for f in os.listdir(clean_dir) if f.endswith(".csv"))
    evil_files = sorted(f for f in os.listdir(evil_dir) if f.endswith(".csv"))
    _run_and_check_filter(script_path, clean_dir, {f: "CLEAN" for f in clean_files})
    _run_and_check_filter(script_path, evil_dir, {f: "EVIL" for f in evil_files})

    # Exercise the classifier on freshly generated, unpredictably named data
    # so fixed output for the shipped corpus cannot pass.
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as root:
        clean_dynamic = os.path.join(root, "clean")
        evil_dynamic = os.path.join(root, "evil")
        os.mkdir(clean_dynamic)
        os.mkdir(evil_dynamic)
        expected_clean = {}
        expected_evil = {}
        for _ in range(7):
            name = f"trajectory_{rng.getrandbits(64):016x}.csv"
            _write_trajectory(os.path.join(clean_dynamic, name), False, rng)
            expected_clean[name] = "CLEAN"
        for _ in range(7):
            name = f"trajectory_{rng.getrandbits(64):016x}.csv"
            _write_trajectory(os.path.join(evil_dynamic, name), True, rng)
            expected_evil[name] = "EVIL"
        _run_and_check_filter(script_path, clean_dynamic, expected_clean)
        _run_and_check_filter(script_path, evil_dynamic, expected_evil)


def _video_centroids(video_path):
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not open {video_path}"
    result = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        mask = (gray < 80).astype(np.uint8)
        count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, 8)
        assert count > 1, "No dark pendulum blob found in a video frame"
        component = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        result.append((float(centroids[component][0]), float(centroids[component][1])))
    cap.release()
    return result


def test_observational_data():
    script_path = "/home/user/track_pendulum.py"
    path = "/home/user/observational_data.csv"
    assert os.path.isfile(script_path), f"Tracking script {script_path} is missing."

    if os.path.exists(path):
        os.remove(path)
    result = subprocess.run(
        ["python3", script_path], capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, f"Tracking script failed: {result.stderr}"
    assert os.path.isfile(path), f"Observational data file {path} is missing."

    expected = _video_centroids("/app/video/experiment_run.mp4")
    with open(path, "r", newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames is not None
        assert all(name in reader.fieldnames for name in ("frame_index", "x", "y")), (
            f"Wrong CSV columns: {reader.fieldnames}"
        )
        rows = list(reader)

    assert len(rows) == len(expected), (
        f"Expected one trajectory row for each of {len(expected)} frames, got {len(rows)}"
    )
    seen = set()
    for row in rows:
        frame_index = int(row["frame_index"])
        assert frame_index not in seen, f"Duplicate frame {frame_index}"
        seen.add(frame_index)
        assert 0 <= frame_index < len(expected), f"Invalid frame index {frame_index}"
        x = float(row["x"])
        y = float(row["y"])
        ex, ey = expected[frame_index]
        assert math.isfinite(x) and math.isfinite(y)
        assert abs(x - ex) <= 2.0 and abs(y - ey) <= 2.0, (
            f"Frame {frame_index} centroid ({x}, {y}) differs from video ({ex}, {ey})"
        )
    assert seen == set(range(len(expected))), "Some video frames are missing from the CSV"

    # Keep the original frame-60 assertion.
    frame_60_x = None
    with open(path, "r") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if row.get("frame_index") == "60":
                frame_60_x = float(row["x"])
                break
    assert frame_60_x is not None, "Frame 60 is missing from observational_data.csv"
    expected_x = 320 + 150 * 1 * math.exp(-0.015 * 60)
    assert abs(frame_60_x - expected_x) <= 2.0, (
        f"Frame 60 X coordinate {frame_60_x} is not within 2 pixels of expected {expected_x}"
    )


def _build_instrumented_mse(output_so):
    source = output_so + ".c"
    with open(source, "w") as handle:
        handle.write(r'''#include <stdio.h>
#include <stdlib.h>

double compute_mse(double* arr1, double* arr2, int length) {
    double sum = 0.0;
    for (int i = 0; i < length; ++i) {
        double d = arr1[i] - arr2[i];
        sum += d * d;
    }
    double value = sum / length;
    const char *log_path = getenv("FAST_MSE_CALL_LOG");
    if (log_path) {
        FILE *f = fopen(log_path, "a");
        if (f) {
            fprintf(f, "%d %.17g\n", length, value);
            fclose(f);
        }
    }
    return value;
}
''')
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", source, "-o", output_so],
        check=True,
        capture_output=True,
        text=True,
    )


def test_model_params():
    script_path = "/home/user/fit_model.py"
    path = "/home/user/model_params.json"
    lib_path = "/home/user/src/fast_mse.so"
    assert os.path.isfile(script_path), f"Fitting script {script_path} is missing."
    assert os.path.isfile(lib_path), f"Compiled shared library {lib_path} is missing."

    with open("/home/user/observational_data.csv", newline="") as handle:
        observation_count = sum(1 for _ in csv.DictReader(handle))

    temp_dir = tempfile.mkdtemp(prefix="mse_verify_")
    instrumented = os.path.join(temp_dir, "fast_mse.so")
    backup = os.path.join(temp_dir, "submitted_fast_mse.so")
    call_log = os.path.join(temp_dir, "calls.log")
    _build_instrumented_mse(instrumented)

    # The replacement computes the same MSE, but records calls. Running the fit
    # against it proves the fitting script actually loads and uses fast_mse.so.
    os.replace(lib_path, backup)
    shutil.copy2(instrumented, lib_path)
    try:
        if os.path.exists(path):
            os.remove(path)
        env = os.environ.copy()
        env["FAST_MSE_CALL_LOG"] = call_log
        result = subprocess.run(
            ["python3", script_path],
            capture_output=True,
            text=True,
            timeout=240,
            env=env,
        )
        assert result.returncode == 0, f"Fitting script failed: {result.stderr}"
    finally:
        if os.path.exists(lib_path):
            os.remove(lib_path)
        os.replace(backup, lib_path)

    assert os.path.isfile(path), f"Model parameters file {path} is missing."
    assert os.path.isfile(call_log), "fit_model.py did not call compute_mse through fast_mse.so"
    calls = []
    with open(call_log) as handle:
        for line in handle:
            parts = line.split()
            assert len(parts) == 2, f"Malformed MSE call record: {line!r}"
            calls.append((int(parts[0]), float(parts[1])))
    full_calls = [value for length, value in calls if length == observation_count]
    assert len(full_calls) >= 2, (
        "The fitting loop must repeatedly compute MSE over the complete observational dataset"
    )
    previous, current = full_calls[-2], full_calls[-1]
    assert math.isfinite(previous) and math.isfinite(current)
    relative_change = abs(current - previous) / max(abs(previous), 1e-300)
    assert relative_change < 1e-6, (
        f"Final successive MSE values did not satisfy convergence: relative change {relative_change}"
    )

    with open(path, "r") as handle:
        try:
            params = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    for key in ("A", "omega", "phi", "gamma", "C"):
        assert key in params, f"Key {key!r} missing from model_params.json"
        assert math.isfinite(float(params[key])), f"Parameter {key} is not finite"

    gamma = float(params["gamma"])
    omega = float(params["omega"])
    expected_gamma = 0.015
    expected_omega = 0.1047
    assert abs(gamma - expected_gamma) / expected_gamma <= 0.05, (
        f"Gamma {gamma} is not within 5% of {expected_gamma}"
    )
    assert abs(omega - expected_omega) / expected_omega <= 0.05, (
        f"Omega {omega} is not within 5% of {expected_omega}"
    )

    # Ensure all five saved parameters jointly describe the extracted data.
    t_values = []
    x_values = []
    with open("/home/user/observational_data.csv", newline="") as handle:
        for row in csv.DictReader(handle):
            t_values.append(float(row["frame_index"]))
            x_values.append(float(row["x"]))
    t = np.asarray(t_values, dtype=np.float64)
    x = np.asarray(x_values, dtype=np.float64)
    prediction = (
        float(params["A"])
        * np.cos(omega * t + float(params["phi"]))
        * np.exp(-gamma * t)
        + float(params["C"])
    )
    fitted_mse = float(np.mean((x - prediction) ** 2))
    assert fitted_mse <= 2.0, f"Saved parameters do not fit the observations; MSE={fitted_mse}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
