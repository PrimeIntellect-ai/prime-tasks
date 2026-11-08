#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import uuid

import numpy as np
import pytest
import torch
import torch.nn as nn
from PIL import Image

DETECTOR = "/home/user/detector.py"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
WEIGHTS = "/app/ae_weights.pth"
VIDEO = "/app/unlabeled_video.mp4"


class Autoencoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.encoder = nn.Sequential(
            nn.Conv2d(3, 16, 3, stride=2, padding=1),
            nn.ReLU(),
        )
        self.decoder = nn.Sequential(
            nn.ConvTranspose2d(16, 3, 3, stride=2, padding=1, output_padding=1),
            nn.Sigmoid(),
        )

    def forward(self, x):
        return self.decoder(self.encoder(x))


@pytest.fixture(scope="session")
def reference():
    model = Autoencoder()
    try:
        state = torch.load(WEIGHTS, map_location="cpu", weights_only=True)
    except TypeError:
        state = torch.load(WEIGHTS, map_location="cpu")
    model.load_state_dict(state)
    model.eval()

    def mse(path):
        with Image.open(path) as image:
            image = image.convert("RGB").resize((64, 64))
            array = np.asarray(image, dtype=np.float32) / 255.0
        tensor = torch.from_numpy(array).permute(2, 0, 1).unsqueeze(0)
        with torch.no_grad():
            output = model(tensor)
            return torch.mean((tensor - output) ** 2).item()

    clean_scores = [mse(os.path.join(CLEAN_DIR, name)) for name in os.listdir(CLEAN_DIR)]
    evil_scores = [mse(os.path.join(EVIL_DIR, name)) for name in os.listdir(EVIL_DIR)]
    clean_max = max(clean_scores)
    evil_min = min(evil_scores)
    assert clean_max < evil_min, "Provided calibration corpora are not separable by MSE"
    return mse, clean_max, evil_min, (clean_max + evil_min) / 2.0


def run_detector(path):
    return subprocess.run(
        [DETECTOR, path], capture_output=True, timeout=30, check=False
    ).returncode


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR), f"Detector script not found at {DETECTOR}"
    assert os.access(DETECTOR, os.X_OK), f"Detector script at {DETECTOR} is not executable"
    with open(DETECTOR, "rb") as handle:
        first_line = handle.readline().rstrip(b"\r\n")
    assert first_line == b"#!/usr/bin/env python3", "Detector has the wrong or missing shebang"


def test_detector_clean_corpus():
    assert os.path.isdir(CLEAN_DIR), "Clean corpus directory missing"
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR)
                   if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, "No clean files found"
    failed_files = [os.path.basename(img) for img in clean_files if run_detector(img) != 0]
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected "
                    f"(expected exit code 0). Offending files: {', '.join(failed_files)}")


def test_detector_evil_corpus():
    assert os.path.isdir(EVIL_DIR), "Evil corpus directory missing"
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR)
                  if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(evil_files) > 0, "No evil files found"
    failed_files = [os.path.basename(img) for img in evil_files if run_detector(img) != 1]
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed "
                    f"(expected exit code 1). Offending files: {', '.join(failed_files)}")


def test_detector_on_unseen_random_paths(reference):
    mse, clean_max, evil_min, _ = reference
    rng = np.random.default_rng()

    with tempfile.TemporaryDirectory(prefix="detector-hidden-") as directory:
        selected = []

        # Generate previously unseen solid-color images and retain examples whose
        # reference MSE is unambiguously inside the clean calibration range.
        for _ in range(500):
            color = rng.integers(0, 256, size=(1, 1, 3), dtype=np.uint8)
            array = np.broadcast_to(color, (64, 64, 3)).copy()
            path = os.path.join(directory, uuid.uuid4().hex + ".png")
            Image.fromarray(array, "RGB").save(path)
            if mse(path) <= clean_max:
                selected.append((path, 0))
                if sum(expected == 0 for _, expected in selected) == 4:
                    break
            else:
                os.unlink(path)

        # Generate previously unseen noisy images and retain examples whose
        # reference MSE is unambiguously inside the corrupted range.
        for _ in range(500):
            array = rng.integers(0, 256, size=(64, 64, 3), dtype=np.uint8)
            path = os.path.join(directory, uuid.uuid4().hex + ".png")
            Image.fromarray(array, "RGB").save(path)
            if mse(path) >= evil_min:
                selected.append((path, 1))
                if sum(expected == 1 for _, expected in selected) == 4:
                    break
            else:
                os.unlink(path)

        assert sum(expected == 0 for _, expected in selected) == 4
        assert sum(expected == 1 for _, expected in selected) == 4
        failures = []
        for path, expected in selected:
            actual = run_detector(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
        assert not failures, f"Detector failed reference-derived hidden cases: {failures}"


def test_extracted_frames():
    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), f"Frames directory not found at {frames_dir}"

    expected_frames = [f"{i:03d}.png" for i in range(1, 11)]
    actual_frames = set(os.listdir(frames_dir))
    missing = set(expected_frames) - actual_frames
    assert not missing, f"Missing extracted frames: {sorted(missing)}"
    assert actual_frames == set(expected_frames), f"Unexpected frame files: {sorted(actual_frames - set(expected_frames))}"

    with tempfile.TemporaryDirectory(prefix="reference-frames-") as directory:
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", VIDEO,
             "-vf", "fps=1", os.path.join(directory, "%03d.png")],
            check=True, timeout=60,
        )
        for name in expected_frames:
            submitted_path = os.path.join(frames_dir, name)
            reference_path = os.path.join(directory, name)
            assert os.path.isfile(submitted_path), f"Frame is not a regular file: {name}"
            with Image.open(submitted_path) as submitted, Image.open(reference_path) as expected:
                submitted_array = np.asarray(submitted.convert("RGB"))
                expected_array = np.asarray(expected.convert("RGB"))
            assert submitted_array.shape == expected_array.shape, f"Wrong dimensions for {name}"
            assert np.array_equal(submitted_array, expected_array), f"{name} is not the corresponding 1 fps video frame"


def test_clean_frames_txt(reference):
    txt_path = "/home/user/clean_frames.txt"
    assert os.path.isfile(txt_path), f"Clean frames list not found at {txt_path}"
    with open(txt_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    # Preserve the original expected-result assertion.
    expected = [
        "001.png",
        "002.png",
        "004.png",
        "005.png",
        "006.png",
        "009.png",
        "010.png",
    ]
    assert lines == expected, f"Expected clean frames list to be {expected}, but got {lines}"

    # Independently derive the result from the supplied model and the calibrated
    # corpus separation, rather than trusting filenames or fabricated frames.
    mse, _, _, threshold = reference
    frames_dir = "/home/user/frames"
    derived = sorted(
        name for name in os.listdir(frames_dir)
        if name.endswith(".png") and mse(os.path.join(frames_dir, name)) < threshold
    )
    assert lines == derived, f"clean_frames.txt does not match model-derived classifications: {derived}"

    detector_derived = sorted(
        name for name in os.listdir(frames_dir)
        if name.endswith(".png") and run_detector(os.path.join(frames_dir, name)) == 0
    )
    assert lines == detector_derived, "clean_frames.txt does not match detector.py results"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
