#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import uuid

import cv2
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/detect_stutter.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def run_classifier(video_path):
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, video_path],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0:
            return None, f"Script exited with code {result.returncode}. Stderr: {result.stderr.strip()}"
        output = result.stdout.strip()
        return output, None
    except subprocess.TimeoutExpired:
        return None, "Script timed out after 30 seconds."
    except Exception as e:
        return None, f"Execution error: {str(e)}"


def test_classifier_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_adversarial_corpus():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    clean_videos = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.mp4')]
    evil_videos = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.mp4')]

    assert len(clean_videos) > 0, "No clean videos found to test."
    assert len(evil_videos) > 0, "No evil videos found to test."

    clean_failures = []
    evil_failures = []

    for video in clean_videos:
        output, err = run_classifier(video)
        if err:
            clean_failures.append((os.path.basename(video), err))
        elif output != "CLEAN":
            clean_failures.append((os.path.basename(video), f"Expected 'CLEAN', got '{output}'"))

    for video in evil_videos:
        output, err = run_classifier(video)
        if err:
            evil_failures.append((os.path.basename(video), err))
        elif output != "EVIL":
            evil_failures.append((os.path.basename(video), f"Expected 'EVIL', got '{output}'"))

    total_clean = len(clean_videos)
    total_evil = len(evil_videos)

    error_msg = []
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {total_clean} clean modified/failed:")
        for f, err in clean_failures:
            error_msg.append(f"  - {f}: {err}")

    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {total_evil} evil bypassed/failed:")
        for f, err in evil_failures:
            error_msg.append(f"  - {f}: {err}")

    if error_msg:
        pytest.fail("\n".join(error_msg))


def write_runtime_video(path, pulse_frames, background):
    writer = cv2.VideoWriter(
        str(path), cv2.VideoWriter_fourcc(*"mp4v"), 30, (100, 100), False
    )
    assert writer.isOpened(), f"Could not create runtime video {path}"
    for pulse_on in pulse_frames:
        frame = background.copy()
        frame[25:75, 25:75] = 255 if pulse_on else 0
        writer.write(frame)
    writer.release()
    assert path.exists() and path.stat().st_size > 0, f"Runtime video was not created: {path}"


def test_runtime_generated_content_corpus(tmp_path):
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    secure = secrets.SystemRandom()
    labels = ["CLEAN"] * 3 + ["EVIL"] * 3
    secure.shuffle(labels)
    cases = []

    for expected in labels:
        name = f"{uuid.uuid4().hex}.mp4"
        path = tmp_path / name
        seed = secrets.randbits(64)
        rng = np.random.default_rng(seed)
        background = rng.integers(0, 24, size=(100, 100), dtype=np.uint8)

        if expected == "CLEAN":
            phase = secure.randrange(3)
            frames = [1 if (i + phase) % 3 == 0 else 0 for i in range(300)]
        else:
            delays = []
            while len(set(delays)) < 2:
                delays = [secure.randint(2, 6) for _ in range(100)]
            frames = []
            for delay in delays:
                frames.append(1)
                frames.extend([0] * delay)
                if len(frames) >= 300:
                    break
            frames = frames[:300]
            if len(frames) < 300:
                frames.extend([0] * (300 - len(frames)))

        write_runtime_video(path, frames, background)
        cases.append((path, expected))

    failures = []
    for path, expected in cases:
        output, err = run_classifier(str(path))
        if err:
            failures.append((path.name, err))
        elif output != expected:
            failures.append((path.name, f"Expected '{expected}', got '{output}'"))

    if failures:
        pytest.fail("Runtime-generated corpus failures:\n" + "\n".join(
            f"  - {name}: {error}" for name, error in failures
        ))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
