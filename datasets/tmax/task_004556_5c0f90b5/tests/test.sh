#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import cv2
import numpy as np
import pytest
from PIL import Image


def run_detector(script_path, image_path):
    result = subprocess.run(
        ["python3", script_path, image_path],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Detector exited with status {result.returncode}: {result.stderr}"
    assert result.stderr == "", f"Detector wrote unexpected stderr: {result.stderr!r}"
    return result.stdout.strip()


def test_detector_script_exists():
    script_path = "/home/user/detector.py"
    assert os.path.isfile(script_path), f"Detector script not found at {script_path}"


def test_detector_adversarial_corpus():
    script_path = "/home/user/detector.py"
    evil_dir = "/app/corpora/test/evil/"
    clean_dir = "/app/corpora/test/clean/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_modified = []

    for filepath in evil_files:
        output = run_detector(script_path, filepath)
        if output != "EVIL":
            evil_bypassed.append(os.path.basename(filepath))

    for filepath in clean_files:
        output = run_detector(script_path, filepath)
        if output != "CLEAN":
            clean_modified.append(os.path.basename(filepath))

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:5])}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified[:5])}")

    assert not evil_bypassed and not clean_modified, " | ".join(error_msg)


def test_detector_on_unlabeled_generated_images():
    script_path = "/home/user/detector.py"
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    cases = []

    # Pair clean and corrupted versions of varied images so path and filename do
    # not reveal the expected result.
    for i in range(12):
        if i == 0:
            base = np.zeros((100, 100, 3), dtype=np.uint8)
        elif i == 1:
            base = np.full((100, 100, 3), 127, dtype=np.uint8)
        else:
            # Excluding 255 guarantees the clean image contains no pure-red pixel.
            base = rng.integers(0, 255, size=(100, 100, 3), dtype=np.uint8)

        cases.append((base.copy(), "CLEAN"))
        corrupted = base.copy()
        y = int(rng.integers(0, 91))
        x = int(rng.integers(0, 91))
        corrupted[y:y + 10, x:x + 10] = (255, 0, 0)
        cases.append((corrupted, "EVIL"))

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="detector_inputs_") as tmpdir:
        for image, expected in cases:
            path = os.path.join(tmpdir, secrets.token_hex(16) + ".png")
            Image.fromarray(image, mode="RGB").save(path)
            actual = run_detector(script_path, path)
            assert actual == expected, f"Detector returned {actual!r}, expected {expected!r} for an unlabeled generated image"


def test_video_clean_frames_txt():
    txt_path = "/home/user/video_clean_frames.txt"
    assert os.path.isfile(txt_path), f"Clean frames file not found at {txt_path}"

    with open(txt_path, "r") as f:
        lines = f.read().strip().splitlines()

    extracted_frames = []
    for line in lines:
        try:
            extracted_frames.append(int(line.strip()))
        except ValueError:
            pytest.fail(f"Invalid non-integer line in {txt_path}: {line}")

    expected_frames = [i for i in range(60) if i not in (14, 27, 42, 51)]

    assert extracted_frames == expected_frames, f"Extracted frames do not match expected. Found {len(extracted_frames)} frames, expected {len(expected_frames)}."


def test_clean_dataset_h5():
    h5_path = "/home/user/clean_dataset.h5"
    assert os.path.isfile(h5_path), f"HDF5 dataset not found at {h5_path}"

    try:
        import h5py
    except ImportError:
        pytest.fail("h5py is not installed, cannot verify HDF5 file.")

    expected_indices = [i for i in range(60) if i not in (14, 27, 42, 51)]
    capture = cv2.VideoCapture("/app/dashcam_raw.mp4")
    assert capture.isOpened(), "Could not decode source video"

    decoded = []
    while True:
        ok, bgr = capture.read()
        if not ok:
            break
        decoded.append(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
    capture.release()
    assert len(decoded) == 60, f"Expected 60 source frames, decoded {len(decoded)}"

    with h5py.File(h5_path, "r") as f:
        assert "images" in f, "Dataset 'images' not found in HDF5 file."
        assert list(f.keys()) == ["images"], "HDF5 file must contain only the 'images' dataset."
        dataset = f["images"]

        expected_shape = (56, 720, 1280, 3)
        assert dataset.shape == expected_shape, f"Dataset shape {dataset.shape} does not match expected {expected_shape}."
        assert dataset.dtype == "uint8", f"Dataset dtype {dataset.dtype} does not match expected uint8."
        assert dataset.compression is None, f"Dataset must be uncompressed, found compression={dataset.compression!r}."

        for output_index, source_index in enumerate(expected_indices):
            actual = dataset[output_index]
            expected = decoded[source_index]
            assert np.array_equal(actual, expected), (
                f"HDF5 image {output_index} does not exactly match clean source frame "
                f"{source_index} in RGB chronological order."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
