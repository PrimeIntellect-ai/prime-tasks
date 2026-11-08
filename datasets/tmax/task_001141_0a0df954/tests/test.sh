#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import json
import os
import subprocess
import tempfile
import uuid

import cv2
import numpy as np

SCRIPT = "/home/user/filter_dataset.py"
REPORT = "/home/user/report.json"
IMAGE_EXTS = (".jpg", ".png")


def image_files(path):
    return sorted(
        name for name in os.listdir(path)
        if os.path.isfile(os.path.join(path, name)) and name.lower().endswith(IMAGE_EXTS)
    )


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def load_report():
    assert os.path.exists(REPORT), "report.json is missing"
    with open(REPORT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "report.json is not valid JSON"
    assert set(data) == {"total_raw_frames", "total_clean_frames", "cv_accuracy"}, \
        f"report.json must contain exactly the required keys, got {sorted(data)}"
    return data


def test_report_json():
    data = load_report()
    assert isinstance(data["total_raw_frames"], int) and not isinstance(data["total_raw_frames"], bool)
    assert data["total_raw_frames"] == 60, f"total_raw_frames should be 60, got {data['total_raw_frames']}"
    assert isinstance(data["total_clean_frames"], int) and not isinstance(data["total_clean_frames"], bool)
    assert data["total_clean_frames"] == 50, f"total_clean_frames should be 50, got {data['total_clean_frames']}"
    assert isinstance(data["cv_accuracy"], (int, float)) and not isinstance(data["cv_accuracy"], bool), \
        "cv_accuracy must be a number"
    assert 0.90 <= data["cv_accuracy"] <= 1.0, \
        f"cv_accuracy should be between 0.90 and 1.0, got {data['cv_accuracy']}"


def test_saved_model_exists():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} not found"
    model_extensions = {
        ".pkl", ".pickle", ".joblib", ".sav", ".model", ".bin", ".ubj",
        ".onnx", ".npz", ".npy", ".xml", ".yml", ".yaml", ".json"
    }
    candidates = []
    for root in ("/home/user", "/app"):
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if os.path.join(directory, d) not in {
                "/home/user/raw_frames", "/home/user/clean_frames",
                "/app/corpus/clean", "/app/corpus/evil"
            }]
            for name in files:
                path = os.path.join(directory, name)
                if path in {SCRIPT, REPORT, "/app/experiment_video.mp4"}:
                    continue
                if os.path.splitext(name)[1].lower() in model_extensions and os.path.getsize(path) > 0:
                    candidates.append(path)
    assert candidates, "No non-empty saved model artifact was found on disk"


def test_frames_extracted_and_contents():
    raw_dir = "/home/user/raw_frames"
    clean_dir = "/home/user/clean_frames"
    assert os.path.isdir(raw_dir), "raw_frames directory is missing"
    assert os.path.isdir(clean_dir), "clean_frames directory is missing"

    raw_names = image_files(raw_dir)
    clean_names = image_files(clean_dir)
    expected_names = [f"frame_{i:03d}.jpg" for i in range(1, 61)]
    assert raw_names == expected_names, "Raw frames must be the 60 correctly named one-frame-per-second JPEGs"
    assert len(clean_names) == 50, f"Expected exactly 50 clean frames, found {len(clean_names)}"

    with tempfile.TemporaryDirectory(prefix="video_reference_") as reference:
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", "/app/experiment_video.mp4", "-vf", "fps=1",
            os.path.join(reference, "frame_%03d.jpg")
        ], check=True)
        reference_names = image_files(reference)
        assert reference_names == expected_names, "Reference video did not decode to 60 frames"

        expected_clean = set()
        for name in expected_names:
            actual = cv2.imread(os.path.join(raw_dir, name), cv2.IMREAD_COLOR)
            wanted = cv2.imread(os.path.join(reference, name), cv2.IMREAD_COLOR)
            assert actual is not None, f"Could not decode raw frame {name}"
            assert wanted is not None and actual.shape == wanted.shape, f"Raw frame {name} has the wrong dimensions"
            mae = float(np.mean(np.abs(actual.astype(np.int16) - wanted.astype(np.int16))))
            assert mae <= 4.0, f"Raw frame {name} does not match the corresponding video frame (MAE {mae:.2f})"
            if float(np.mean(wanted)) > 10.0:
                expected_clean.add(name)

        assert len(expected_clean) == 50, "Reference video should contain 50 usable frames"
        assert set(clean_names) == expected_clean, "clean_frames does not contain exactly the non-black video frames"
        for name in clean_names:
            assert file_hash(os.path.join(clean_dir, name)) == file_hash(os.path.join(raw_dir, name)), \
                f"Filtered frame {name} was modified instead of copied"


def make_holdout(path):
    rng = np.random.default_rng()
    labels = {}

    # Structured, non-corrupt experimental images similar in difficulty to the corpus,
    # but newly generated and placed under unpredictable names in one mixed directory.
    for i in range(50):
        img = np.zeros((100, 100, 3), dtype=np.uint8)
        inset = int(rng.integers(8, 15))
        color = (
            int(rng.integers(105, 196)),
            int(rng.integers(55, 190)),
            int(rng.integers(152, 198)),
        )
        cv2.rectangle(img, (inset, inset), (99 - inset, 99 - inset), color, -1)
        if i % 3 == 0:
            cv2.circle(img, (50, 50), int(rng.integers(8, 18)), tuple(max(1, c - 25) for c in color), -1)
        name = uuid.uuid4().hex + (".png" if i % 2 else ".jpg")
        assert cv2.imwrite(os.path.join(path, name), img)
        labels[name] = True

    for i in range(50):
        if i % 2 == 0:
            img = np.zeros((100, 100, 3), dtype=np.uint8)
        else:
            img = rng.integers(0, 256, (100, 100, 3), dtype=np.uint8)
        name = uuid.uuid4().hex + (".jpg" if i % 2 else ".png")
        assert cv2.imwrite(os.path.join(path, name), img)
        labels[name] = False
    return labels


def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} not found"
    with tempfile.TemporaryDirectory(prefix=uuid.uuid4().hex + "_") as mixed_dir, \
         tempfile.TemporaryDirectory(prefix=uuid.uuid4().hex + "_") as output_dir:
        labels = make_holdout(mixed_dir)
        result = subprocess.run(
            ["python3", SCRIPT, mixed_dir, output_dir],
            capture_output=True, text=True, timeout=120
        )
        assert result.returncode == 0, f"Script failed on holdout corpus:\n{result.stderr}"

        output_names = image_files(output_dir)
        expected = {name for name, clean in labels.items() if clean}
        assert set(output_names) == expected, \
            f"Filtering errors: missing {len(expected - set(output_names))}, unexpected {len(set(output_names) - expected)}"
        assert len(os.listdir(output_dir)) == len(output_names), "Output directory contains unexpected non-image entries"
        for name in output_names:
            assert file_hash(os.path.join(mixed_dir, name)) == file_hash(os.path.join(output_dir, name)), \
                f"Output image {name} was modified instead of copied"

        # The claimed CV score must at least be consistent with the independently
        # observed perfect performance on the balanced hidden holdout.
        report = load_report()
        observed_accuracy = sum((name in set(output_names)) == clean for name, clean in labels.items()) / len(labels)
        assert observed_accuracy == 1.0
        assert report["cv_accuracy"] <= observed_accuracy + 1e-9
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
