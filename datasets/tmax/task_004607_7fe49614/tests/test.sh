#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import re
import shutil
import subprocess
import tempfile
import time
import uuid

import pytest
from PIL import Image, ImageChops, ImageDraw, ImageStat

SCRIPT = "/home/user/filter.sh"
FRAMES_DIR = "/home/user/frames"


def run_filter(path, *extra):
    return subprocess.run(
        [SCRIPT, path, *extra], capture_output=True, timeout=20
    ).returncode


def test_filter_sh_exists_and_executable():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."


def test_frames_are_real_one_fps_extraction():
    assert os.path.isdir(FRAMES_DIR), f"{FRAMES_DIR} does not exist."
    submitted = sorted(glob.glob(os.path.join(FRAMES_DIR, "frame_*.jpg")))

    with tempfile.TemporaryDirectory(prefix="expected_frames_") as td:
        pattern = os.path.join(td, "frame_%03d.jpg")
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
             "-i", "/app/data/video.mp4", "-vf", "fps=1", "-q:v", "2", pattern],
            check=True,
        )
        expected = sorted(glob.glob(os.path.join(td, "frame_*.jpg")))
        expected_names = [os.path.basename(p) for p in expected]

        assert submitted, "No extracted frames were found."
        assert [os.path.basename(p) for p in submitted] == expected_names, (
            "Frames must be the complete sequential 1-fps extraction named frame_001.jpg, etc."
        )

        for actual_path, expected_path in zip(submitted, expected):
            with Image.open(actual_path) as actual_img, Image.open(expected_path) as expected_img:
                actual = actual_img.convert("RGB")
                reference = expected_img.convert("RGB")
                assert actual.size == reference.size, f"Wrong dimensions for {actual_path}."
                diff = ImageChops.difference(actual, reference)
                mean_error = sum(ImageStat.Stat(diff).mean) / 3.0
                assert mean_error < 25.0, (
                    f"{actual_path} does not match the corresponding 1-fps video frame "
                    f"(mean pixel error {mean_error:.2f})."
                )


def neutralized_hidden_cases(kind):
    source_dir = f"/app/hidden_corpus/{kind}"
    if not os.path.exists(source_dir):
        pytest.skip(f"Hidden {kind} corpus not found, skipping.")
    sources = glob.glob(os.path.join(source_dir, "*.jpg")) + glob.glob(os.path.join(source_dir, "*.jpeg"))
    if not sources:
        pytest.skip(f"No images found in hidden {kind} corpus.")
    return sources


def evaluate_mixed_cases(cases):
    failures = []
    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix=f"evaluation_{uuid.uuid4().hex}_") as td:
        for source, expected_code in cases:
            destination = os.path.join(td, f"sample_{uuid.uuid4().hex}.jpg")
            # Re-encode under an unlabeled, unpredictable path rather than exposing
            # /clean/ or /evil/ to the submitted script.
            with Image.open(source) as img:
                img.convert("RGB").save(destination, "JPEG", quality=random.SystemRandom().randint(88, 96))
            code = run_filter(destination)
            if code != expected_code:
                failures.append(os.path.basename(destination))
    return failures


def test_adversarial_corpus_clean_and_evil_without_labelled_paths():
    clean_files = neutralized_hidden_cases("clean")
    evil_files = neutralized_hidden_cases("evil")
    cases = [(p, 0) for p in clean_files] + [(p, 1) for p in evil_files]
    failures = evaluate_mixed_cases(cases)
    assert not failures, (
        f"{len(failures)} of {len(cases)} hidden images were misclassified after being "
        f"placed at neutral paths. Offending files: {failures[:5]}"
    )


def test_filter_generalizes_to_fresh_unlabelled_holdout_images():
    rng = random.SystemRandom()
    cases = []
    with tempfile.TemporaryDirectory(prefix="fresh_holdout_sources_") as source_dir:
        for label in (0, 1):
            for _ in range(12):
                color = tuple(rng.randint(0, 200) for _ in range(3))
                img = Image.new("RGB", (640, 480), color=color)
                if label == 1:
                    ImageDraw.Draw(img).rectangle([100, 100, 200, 200], fill="red")
                source = os.path.join(source_dir, f"{uuid.uuid4().hex}.jpg")
                img.save(source, "JPEG", quality=rng.randint(90, 97))
                cases.append((source, label))
        failures = evaluate_mixed_cases(cases)

    assert not failures, (
        f"{len(failures)} of {len(cases)} freshly generated holdout images were "
        f"misclassified. Offending files: {failures[:5]}"
    )


def test_anomalies_txt():
    anomalies_path = "/home/user/anomalies.txt"
    assert os.path.exists(anomalies_path), f"{anomalies_path} does not exist."

    with open(anomalies_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, "anomalies.txt is empty."

    numbers = []
    for line in lines:
        match = re.search(r"\d+", line)
        if match:
            numbers.append(int(match.group()))

    assert len(numbers) >= 6 and len(numbers) <= 8, f"Expected around 7 anomalies, found {len(numbers)}: {lines}"
    numbers.sort()
    assert numbers[-1] - numbers[0] == len(numbers) - 1, f"Anomalies are not consecutive frames: {lines}"

    assert len(lines) == len(set(lines)), "anomalies.txt contains duplicate entries."
    frame_names = {os.path.basename(p) for p in glob.glob(os.path.join(FRAMES_DIR, "frame_*.jpg"))}
    assert all(line in frame_names for line in lines), "anomalies.txt must contain only extracted frame filenames."

    # The source video has its anomaly from 12 through 18 seconds. Allow the
    # normal one-frame indexing boundary variation, but not an arbitrary run.
    assert set(numbers).issubset(set(range(12, 20))), f"Anomalies are outside the video's anomalous interval: {lines}"
    assert set(range(13, 19)).issubset(set(numbers)), f"Core anomalous frames are missing: {lines}"

    actual = []
    for path in sorted(glob.glob(os.path.join(FRAMES_DIR, "frame_*.jpg"))):
        code = run_filter(path)
        assert code in (0, 1), f"filter.sh returned invalid status {code} for {path}."
        if code == 1:
            actual.append(os.path.basename(path))
    assert lines == actual, "anomalies.txt does not match running filter.sh over the extracted frames in order."


def test_fps_txt():
    fps_path = "/home/user/fps.txt"
    assert os.path.exists(fps_path), f"{fps_path} does not exist."

    with open(fps_path, "r") as f:
        content = f.read().strip()

    assert re.fullmatch(r"(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", content), (
        f"fps.txt does not contain a single numerical value: {content}"
    )
    try:
        fps_val = float(content)
        assert math.isfinite(fps_val) and fps_val > 0, "FPS must be finite and greater than 0."
    except ValueError:
        pytest.fail(f"fps.txt does not contain a valid number: {content}")

    frames = sorted(glob.glob(os.path.join(FRAMES_DIR, "frame_*.jpg")))
    assert frames, "Cannot benchmark because no extracted frames exist."
    start = time.perf_counter()
    for frame in frames:
        code = run_filter(frame)
        assert code in (0, 1), f"filter.sh returned invalid status {code} while benchmarking."
    elapsed = time.perf_counter() - start
    measured_fps = len(frames) / elapsed
    ratio = fps_val / measured_fps
    assert 0.2 <= ratio <= 5.0, (
        f"Reported FPS {fps_val} is not consistent with measured filter throughput "
        f"{measured_fps:.3f} FPS."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
