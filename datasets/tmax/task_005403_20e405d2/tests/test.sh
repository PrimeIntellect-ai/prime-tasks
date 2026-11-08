#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import random
import shutil
import subprocess
import tempfile
import uuid

import numpy as np
from PIL import Image

SCRIPT = "/home/user/detect_corruption.py"
FRAMES_DIR = "/home/user/extracted_frames"
REPORT = "/home/user/frame_report.csv"
EXPECTED_NAMES = [f"frame_{i:04d}.jpg" for i in range(1, 61)]


def run_classifier(path):
    result = subprocess.run(
        ["python3", SCRIPT, path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Classifier failed for {path}: rc={result.returncode}, stderr={result.stderr!r}"
    )
    output = result.stdout.strip()
    assert output in {"CLEAN", "EVIL"}, (
        f"Classifier must print exactly CLEAN or EVIL for {path}, got {result.stdout!r}"
    )
    return output


def test_extracted_frames():
    assert os.path.isdir(FRAMES_DIR), f"Extracted frames directory is missing: {FRAMES_DIR}"

    frames = [f for f in os.listdir(FRAMES_DIR) if f.endswith(".jpg")]
    assert len(frames) == 60, f"Expected 60 extracted frames, found {len(frames)}"

    # Preserve the original naming assertion and require the complete, unique sequence.
    for frame in frames:
        assert frame.startswith("frame_") and frame.endswith(".jpg"), f"Invalid frame name: {frame}"
    assert sorted(frames) == EXPECTED_NAMES, f"Frames must be named exactly frame_0001.jpg through frame_0060.jpg"

    with tempfile.TemporaryDirectory(prefix="reference_extract_") as reference_dir:
        pattern = os.path.join(reference_dir, "frame_%04d.jpg")
        result = subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", "/app/conveyor.mp4", "-vf", "fps=1", pattern,
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, f"Reference ffmpeg extraction failed: {result.stderr}"
        reference_names = sorted(f for f in os.listdir(reference_dir) if f.endswith(".jpg"))
        assert reference_names == EXPECTED_NAMES, "Reference extraction did not produce 60 one-fps frames"

        content_hashes = set()
        for name in EXPECTED_NAMES:
            submitted_path = os.path.join(FRAMES_DIR, name)
            reference_path = os.path.join(reference_dir, name)
            assert os.path.isfile(submitted_path), f"Missing extracted frame: {name}"

            with Image.open(submitted_path) as image:
                submitted = np.asarray(image.convert("RGB"), dtype=np.float32)
            with Image.open(reference_path) as image:
                reference = np.asarray(image.convert("RGB"), dtype=np.float32)

            assert submitted.shape == reference.shape, f"Wrong dimensions for {name}"
            mean_error = float(np.mean(np.abs(submitted - reference)))
            assert mean_error < 12.0, (
                f"{name} does not match the corresponding one-fps video frame "
                f"(mean absolute pixel error {mean_error:.2f})"
            )
            content_hashes.add(hashlib.sha256(submitted.tobytes()).hexdigest())

        assert len(content_hashes) == 60, "Extracted frames must contain 60 distinct frame images"


def test_classifier_script_exists():
    assert os.path.isfile(SCRIPT), f"Classifier script is missing: {SCRIPT}"


def test_adversarial_corpus_classification():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".jpg")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".jpg")]
    assert len(clean_files) > 0, "No clean files found"
    assert len(evil_files) > 0, "No evil files found"

    clean_failures = [os.path.basename(f) for f in clean_files if run_classifier(f) != "CLEAN"]
    evil_failures = [os.path.basename(f) for f in evil_files if run_classifier(f) != "EVIL"]
    error_msg = []
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (failed to return CLEAN): {', '.join(clean_failures)}")
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed (failed to return EVIL): {', '.join(evil_failures)}")
    assert not error_msg, " | ".join(error_msg)

    # Re-test corpus pixels under random, label-free paths so directory names cannot be used.
    with tempfile.TemporaryDirectory(prefix="neutral_images_") as neutral_dir:
        copied = []
        for source, expected in [(p, "CLEAN") for p in clean_files] + [(p, "EVIL") for p in evil_files]:
            destination = os.path.join(neutral_dir, uuid.uuid4().hex + ".jpg")
            shutil.copyfile(source, destination)
            copied.append((destination, expected))
        random.SystemRandom().shuffle(copied)
        for path, expected in copied:
            assert run_classifier(path) == expected, "Classification changed when an image was renamed"


def test_classifier_on_derived_unseen_inputs():
    # Labels are derived from how each new image is constructed, while all paths are random.
    rng = np.random.default_rng()
    cases = []
    with tempfile.TemporaryDirectory(prefix="unseen_pixels_") as image_dir:
        for expected in (["CLEAN"] * 12 + ["EVIL"] * 12):
            height = int(rng.integers(88, 125))
            width = int(rng.integers(88, 125))
            pixels = rng.integers(0, 256, (height, width, 3), dtype=np.uint8)
            if expected == "EVIL":
                pixels[:, :, 1] = 128
            path = os.path.join(image_dir, uuid.uuid4().hex + ".jpg")
            Image.fromarray(pixels).save(path, format="JPEG", quality=int(rng.choice([75, 85, 95])))
            cases.append((path, expected))

        random.SystemRandom().shuffle(cases)
        for path, expected in cases:
            assert run_classifier(path) == expected, (
                f"Classifier failed an unseen pixel-derived {expected} case"
            )


def test_frame_report():
    assert os.path.isfile(REPORT), f"Report file missing: {REPORT}"
    with open(REPORT, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, "Report is empty"
    assert rows[0] == ["filename", "status"], f"Invalid header: {rows[0]}"
    data_rows = rows[1:]
    assert len(data_rows) == 60, f"Expected 60 data rows in report, found {len(data_rows)}"

    for row in data_rows:
        assert len(row) == 2, f"Invalid row format: {row}"
        assert row[0].startswith("frame_") and row[0].endswith(".jpg"), f"Invalid filename in report: {row[0]}"
        assert row[1] in ["CLEAN", "EVIL"], f"Invalid status in report: {row[1]}"

    reported_names = [row[0] for row in data_rows]
    assert sorted(reported_names) == EXPECTED_NAMES, "Report must contain every extracted filename exactly once"
    reported = dict(data_rows)

    # Require each status to equal an actual classifier result, and repeat the call on
    # a random path to prevent special-casing /home/user/extracted_frames.
    with tempfile.TemporaryDirectory(prefix="report_validation_") as neutral_dir:
        for name in EXPECTED_NAMES:
            source = os.path.join(FRAMES_DIR, name)
            direct_status = run_classifier(source)
            neutral_path = os.path.join(neutral_dir, uuid.uuid4().hex + ".jpg")
            shutil.copyfile(source, neutral_path)
            neutral_status = run_classifier(neutral_path)
            assert direct_status == neutral_status, f"Classifier result for {name} depends on its path"
            assert reported[name] == direct_status, (
                f"Report status for {name} is {reported[name]}, classifier returned {direct_status}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
