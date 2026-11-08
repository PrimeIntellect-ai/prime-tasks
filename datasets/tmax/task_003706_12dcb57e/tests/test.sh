#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

import cv2
import pytest
import requests

CSV_PATH = "/home/user/trajectory.csv"
CPP_PATH = "/home/user/mcmc_sampler.cpp"
PARAM_PATH = "/home/user/parameters.txt"
VIDEO_PATH = "/app/experiment.mp4"


def parse_parameters(path=PARAM_PATH):
    with open(path, "r") as f:
        content = f.read()
    d_match = re.search(r"D=([0-9\.]+)", content)
    alpha_match = re.search(r"alpha=([0-9\.]+)", content)
    assert d_match is not None, f"Could not parse D from {path}."
    assert alpha_match is not None, f"Could not parse alpha from {path}."
    return float(d_match.group(1)), float(alpha_match.group(1))


def load_trajectory():
    with open(CSV_PATH, newline="") as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == 300
    parsed = []
    for i, row in enumerate(rows):
        assert set(row) == {"frame", "x", "y"}
        frame = int(row["frame"])
        x = float(row["x"])
        y = float(row["y"])
        assert frame == i, f"Expected frame index {i}, got {frame}."
        assert math.isfinite(x) and math.isfinite(y)
        parsed.append((frame, x, y))
    return parsed


def test_trajectory_csv_exists_and_format():
    """Check that trajectory.csv exists and has the correct format and length."""
    assert os.path.exists(CSV_PATH), f"File {CSV_PATH} does not exist."
    with open(CSV_PATH, "r") as f:
        lines = f.read().strip().split("\n")
    assert len(lines) > 1, f"{CSV_PATH} is empty or missing data."
    assert lines[0].strip() == "frame,x,y", "Header is incorrect. Expected 'frame,x,y'."
    assert len(lines) == 301, f"Expected 300 frames (301 lines including header), got {len(lines)}."
    load_trajectory()


def test_trajectory_matches_bright_particle_in_video():
    submitted = load_trajectory()
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open {VIDEO_PATH}."
    detected = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if frame.ndim == 3 else frame
        maximum = float(gray.max())
        assert maximum > 0, "Video frame has no bright particle."
        mask = gray >= max(180.0, maximum * 0.80)
        ys, xs = mask.nonzero()
        assert len(xs) > 0
        detected.append((float(xs.mean()), float(ys.mean())))
    cap.release()

    assert len(detected) == 300, f"Expected 300 decoded video frames, got {len(detected)}."
    errors = []
    for (_, x, y), (expected_x, expected_y) in zip(submitted, detected):
        errors.append(math.hypot(x - expected_x, y - expected_y))
    assert max(errors) <= 2.5, f"Trajectory does not track the video's bright particle; max error is {max(errors):.3f}px."
    assert sum(errors) / len(errors) <= 1.25, "Mean tracking error is too large."


def test_mcmc_sampler_cpp_exists():
    """Check that mcmc_sampler.cpp exists."""
    assert os.path.exists(CPP_PATH), f"File {CPP_PATH} does not exist."


def test_mcmc_source_compiles_and_contains_required_mechanisms():
    with open(CPP_PATH, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*pragma\s+omp\s+(parallel|for)", source, re.I), "Sampler must use an OpenMP parallel pragma."
    assert re.search(r"(metropolis|accept|proposal|posterior|markov)", source, re.I), "Source does not appear to implement an MCMC transition."
    assert re.search(r"(<random>|mt19937|random_device|uniform_real_distribution|normal_distribution)", source), "MCMC sampler must use random proposals/acceptance draws."
    result = subprocess.run(
        ["g++", "-O2", "-std=c++17", "-fopenmp", CPP_PATH, "-o", "/tmp/mcmc_sampler_verify"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert result.returncode == 0, f"mcmc_sampler.cpp failed to compile with -fopenmp:\n{result.stderr}"


def test_parameters_txt_exists_and_values():
    """Check that parameters.txt exists and contains valid estimates."""
    assert os.path.exists(PARAM_PATH), f"File {PARAM_PATH} does not exist."
    d_val, alpha_val = parse_parameters()
    assert 1.35 <= d_val <= 1.65, f"Estimated D ({d_val}) is not within 10% of true value 1.5."
    assert 0.675 <= alpha_val <= 0.825, f"Estimated alpha ({alpha_val}) is not within 10% of true value 0.75."


def test_compiled_sampler_executes_and_uses_trajectory_data():
    assert os.path.exists("/tmp/mcmc_sampler_verify"), "Compiled sampler is missing."
    original_csv = open(CSV_PATH, "rb").read()
    original_params = open(PARAM_PATH, "rb").read()
    original_d, _ = parse_parameters()
    rows = load_trajectory()
    x0, y0 = rows[0][1], rows[0][2]
    try:
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["frame", "x", "y"])
            for frame, x, y in rows:
                writer.writerow([frame, x0 + 2.0 * (x - x0), y0 + 2.0 * (y - y0)])
        if os.path.exists(PARAM_PATH):
            os.remove(PARAM_PATH)
        env = os.environ.copy()
        env["OMP_NUM_THREADS"] = "4"
        run = subprocess.run(
            ["/tmp/mcmc_sampler_verify"], cwd="/home/user", env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
        )
        assert run.returncode == 0, f"Compiled sampler failed when executed:\n{run.stderr}"
        assert os.path.exists(PARAM_PATH), "Executing the sampler did not create parameters.txt."
        scaled_d, scaled_alpha = parse_parameters()
        assert math.isfinite(scaled_d) and math.isfinite(scaled_alpha)
        assert scaled_d > original_d * 1.5, "Estimated D did not respond to a twofold scaling of trajectory displacements."
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        with open(PARAM_PATH, "wb") as f:
            f.write(original_params)


def fetch_trajectory(steps):
    url = f"http://localhost:8080/simulate?steps={steps}"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {url}: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}."
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON.")
    assert "trajectory" in data, "JSON response must contain a 'trajectory' key."
    trajectory = data["trajectory"]
    assert isinstance(trajectory, list), "'trajectory' must be a list."
    assert len(trajectory) == steps, f"Expected {steps} steps, got {len(trajectory)}."
    for i, point in enumerate(trajectory):
        assert isinstance(point, dict)
        assert "x" in point, f"Point at index {i} is missing 'x'."
        assert "y" in point, f"Point at index {i} is missing 'y'."
        assert isinstance(point["x"], (int, float)) and not isinstance(point["x"], bool)
        assert isinstance(point["y"], (int, float)) and not isinstance(point["y"], bool)
        assert math.isfinite(point["x"]) and math.isfinite(point["y"])
    assert trajectory[0]["x"] == pytest.approx(0.0, abs=1e-12)
    assert trajectory[0]["y"] == pytest.approx(0.0, abs=1e-12)
    return trajectory


def test_simulation_service():
    """Check varying N, origin, non-degenerate motion, and newly sampled responses."""
    assert len(fetch_trajectory(1)) == 1
    assert len(fetch_trajectory(7)) == 7
    trajectories = [fetch_trajectory(50) for _ in range(4)]
    for trajectory in trajectories:
        assert any(abs(p["x"]) > 1e-12 or abs(p["y"]) > 1e-12 for p in trajectory[1:]), "Simulated trajectory never moves from the origin."
        assert len({(p["x"], p["y"]) for p in trajectory}) > 2, "Simulation returned repeated identical points."
    serialized = [tuple((p["x"], p["y"]) for p in trajectory) for trajectory in trajectories]
    assert len(set(serialized)) > 1, "Repeated requests must return newly simulated trajectories, not a fixed response."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
