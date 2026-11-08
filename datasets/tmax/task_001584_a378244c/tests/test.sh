#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import shutil
import subprocess
import numpy as np
from scipy import stats
import imageio.v3 as iio
import pytest


def validate_extracted_frames(truth_frames_dir, expected_names):
    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), f"Frames directory missing at {frames_dir}"

    actual_names = sorted(
        name for name in os.listdir(frames_dir)
        if name.startswith("frame_") and name.endswith(".jpg")
    )
    assert actual_names == expected_names, (
        f"Expected extracted JPEG frames {expected_names}, got {actual_names}"
    )

    for jpg_name in actual_names:
        jpg_path = os.path.join(frames_dir, jpg_name)
        with open(jpg_path, "rb") as f:
            data = f.read()
        assert data.startswith(b"\xff\xd8") and data.endswith(b"\xff\xd9"), (
            f"{jpg_name} is not a valid JPEG file"
        )

        agent_img = iio.imread(jpg_path)
        truth_name = jpg_name.replace(".jpg", ".png")
        truth_img = iio.imread(os.path.join(truth_frames_dir, truth_name))
        assert agent_img.shape[:2] == truth_img.shape[:2], (
            f"{jpg_name} has incorrect dimensions"
        )
        assert agent_img.ndim == 3 and agent_img.shape[2] >= 3, (
            f"{jpg_name} is not an RGB image"
        )

        mae = np.mean(np.abs(
            agent_img[..., :3].astype(np.float64) -
            truth_img[..., :3].astype(np.float64)
        ))
        assert mae < 8.0, f"{jpg_name} does not match the corresponding video frame"


def test_results_json():
    source_path = "/home/user/analyze_frames.c"
    results_path = "/home/user/results.json"
    executable_path = "/tmp/verifier_analyze_frames"

    assert os.path.isfile(source_path), f"C source file missing at {source_path}"

    # Compute independent truth frames and use them to verify that the requested
    # JPEG extraction was actually left in /home/user/frames.
    truth_frames_dir = "/tmp/truth_frames"
    shutil.rmtree(truth_frames_dir, ignore_errors=True)
    os.makedirs(truth_frames_dir)
    subprocess.run(
        ["ffmpeg", "-y", "-i", "/app/video.mp4", "-vf", "fps=1",
         os.path.join(truth_frames_dir, "frame_%04d.png")],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )

    frames = sorted(os.listdir(truth_frames_dir))
    assert len(frames) > 1, "Not enough frames extracted from video to perform analysis"
    expected_jpegs = [name.replace(".png", ".jpg") for name in frames]
    validate_extracted_frames(truth_frames_dir, expected_jpegs)

    # Compile the submitted C source, remove any precomputed result, and require
    # the compiled artifact itself to recreate results.json.
    compile_result = subprocess.run(
        ["gcc", "-O2", source_path, "-o", executable_path, "-ljpeg", "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, (
        "analyze_frames.c did not compile:\n" + compile_result.stderr
    )
    assert os.path.isfile(executable_path) and os.access(executable_path, os.X_OK), (
        "Compilation did not produce an executable"
    )

    if os.path.exists(results_path):
        os.remove(results_path)

    run_result = subprocess.run(
        [executable_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, (
        "Compiled analyze_frames program failed:\n" + run_result.stderr
    )
    assert os.path.isfile(results_path), (
        "Compiled analyze_frames program did not create /home/user/results.json"
    )

    # Ensure execution did not remove or replace the required extracted frames.
    validate_extracted_frames(truth_frames_dir, expected_jpegs)

    with open(results_path, "r") as f:
        try:
            agent_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not valid JSON")

    # Required keys
    required_keys = [
        "most_similar_frame_file",
        "min_l2_distance",
        "brightness_mean",
        "brightness_ci_lower",
        "brightness_ci_upper"
    ]
    for k in required_keys:
        assert k in agent_results, f"Key '{k}' missing from results.json"

    embeddings = []
    brightnesses = []

    for f in frames:
        img = iio.imread(os.path.join(truth_frames_dir, f))
        avg_color = img.mean(axis=(0, 1))[:3]  # Ensure RGB
        embeddings.append(avg_color)
        brightnesses.append(avg_color.mean())

    embeddings = np.array(embeddings)
    brightnesses = np.array(brightnesses)

    # Similar frame
    ref = embeddings[0]
    dists = np.linalg.norm(embeddings[1:] - ref, axis=1)
    best_idx = np.argmin(dists) + 1
    min_dist = dists[best_idx - 1]
    best_frame_png = frames[best_idx]
    best_frame_jpg = best_frame_png.replace(".png", ".jpg")

    # Confidence Interval
    mean_b = np.mean(brightnesses)
    sem_b = stats.sem(brightnesses)
    ci = stats.t.interval(0.95, len(brightnesses) - 1, loc=mean_b, scale=sem_b)

    # Validate agent results
    agent_frame = agent_results["most_similar_frame_file"]
    assert agent_frame == best_frame_jpg, f"Expected most_similar_frame_file to be {best_frame_jpg}, got {agent_frame}"

    agent_min_l2 = float(agent_results["min_l2_distance"])
    assert abs(agent_min_l2 - min_dist) < 1.0, f"min_l2_distance {agent_min_l2} is not within 1.0 of truth {min_dist}"

    agent_mean = float(agent_results["brightness_mean"])
    assert abs(agent_mean - mean_b) < 0.5, f"brightness_mean {agent_mean} is not within 0.5 of truth {mean_b}"

    agent_ci_lower = float(agent_results["brightness_ci_lower"])
    assert abs(agent_ci_lower - ci[0]) < 0.5, f"brightness_ci_lower {agent_ci_lower} is not within 0.5 of truth {ci[0]}"

    agent_ci_upper = float(agent_results["brightness_ci_upper"])
    assert abs(agent_ci_upper - ci[1]) < 0.5, f"brightness_ci_upper {agent_ci_upper} is not within 0.5 of truth {ci[1]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
