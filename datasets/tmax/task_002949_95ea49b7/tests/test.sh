#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import glob
import secrets
import subprocess
import tempfile

import cv2
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/detect_glitch.py"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"

def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.png"))
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.png"))

    assert len(evil_files) > 0, f"No files found in evil corpus {EVIL_CORPUS_DIR}"
    assert len(clean_files) > 0, f"No files found in clean corpus {CLEAN_CORPUS_DIR}"

    evil_bypassed = []
    clean_modified = []

    for img_path in evil_files:
        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH, img_path],
                capture_output=True,
                text=True,
                timeout=5
            )
            output = result.stdout.strip()
            if output != "GLITCH":
                evil_bypassed.append((os.path.basename(img_path), output))
        except Exception as e:
            evil_bypassed.append((os.path.basename(img_path), str(e)))

    for img_path in clean_files:
        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH, img_path],
                capture_output=True,
                text=True,
                timeout=5
            )
            output = result.stdout.strip()
            if output != "CLEAN":
                clean_modified.append((os.path.basename(img_path), output))
        except Exception as e:
            clean_modified.append((os.path.basename(img_path), str(e)))

    error_messages = []
    if evil_bypassed:
        error_messages.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed. "
            f"Offending files: {', '.join(f[0] for f in evil_bypassed[:5])}"
            f"{'...' if len(evil_bypassed) > 5 else ''}"
        )
    if clean_modified:
        error_messages.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified (failed to identify as CLEAN). "
            f"Offending files: {', '.join(f[0] for f in clean_modified[:5])}"
            f"{'...' if len(clean_modified) > 5 else ''}"
        )

    assert not error_messages, " | ".join(error_messages)


def _create_random_frame(glitch, rng):
    frame = np.zeros((256, 256, 3), dtype=np.uint8)
    offset = rng.randrange(32)
    for i in range(0, 256, 32):
        cv2.line(frame, (i + offset, 0), (i + offset, 255), (128, 128, 128), 1)
        cv2.line(frame, (0, i + offset), (255, i + offset), (128, 128, 128), 1)

    if glitch:
        y = rng.randrange(0, 200)
        height = rng.randrange(10, 50)
        frame[y:y + height, :, :] = [0, 0, 255]
    return frame


def test_runtime_generated_frames_cannot_be_classified_by_path():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    rng = secrets.SystemRandom()
    labels = [False] * 32 + [True] * 32
    rng.shuffle(labels)
    failures = []

    with tempfile.TemporaryDirectory(prefix="mesh_frames_") as frame_dir:
        cases = []
        for glitch in labels:
            # Random opaque names in one shared directory reveal neither class.
            path = os.path.join(frame_dir, secrets.token_hex(16) + ".png")
            frame = _create_random_frame(glitch, rng)
            assert cv2.imwrite(path, frame), f"Failed to create runtime test image {path}"
            cases.append((path, "GLITCH" if glitch else "CLEAN"))

        rng.shuffle(cases)
        for path, expected in cases:
            try:
                result = subprocess.run(
                    ["python3", SCRIPT_PATH, path],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                output = result.stdout.strip()
                if result.returncode != 0 or output != expected:
                    failures.append(
                        (os.path.basename(path), expected, output, result.returncode)
                    )
            except Exception as exc:
                failures.append((os.path.basename(path), expected, str(exc), None))

    assert not failures, (
        f"Detector failed {len(failures)} of {len(labels)} runtime-generated frames. "
        f"Examples: {failures[:5]}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
