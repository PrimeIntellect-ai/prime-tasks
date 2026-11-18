#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile
import uuid

import cv2
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/sanitizer.py"
EVIL_CORPUS_DIR = "/app/corpora/evil"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
VIDEO_PATH = "/app/status_flashes.mp4"


def run_script(filepath):
    try:
        return subprocess.run(
            ["python3", SCRIPT_PATH, filepath],
            capture_output=True,
            timeout=10,
        ).returncode
    except subprocess.TimeoutExpired:
        return None


def video_parameters():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open diagnostic video at {VIDEO_PATH}"
    red = 0
    green = 0
    frames = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames += 1
        # The source frames are solid primary colors. The tolerance accounts for
        # the small value changes introduced by lossy MP4 encoding.
        b, g, r = frame[:, :, 0], frame[:, :, 1], frame[:, :, 2]
        if np.all(r >= 240) and np.all(g <= 15) and np.all(b <= 15):
            red += 1
        if np.all(g >= 240) and np.all(r <= 15) and np.all(b <= 15):
            green += 1
    cap.release()
    assert frames > 0, "Diagnostic video contained no readable frames"
    assert red > 0 and green > 0, "Could not derive positive N and M from the diagnostic video"
    return red, green


def jsonl(events):
    return "".join(json.dumps(event) + "\n" for event in events).encode("utf-8")


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script was not found at {SCRIPT_PATH}"


def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing at {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory."

    failed_files = []
    for filepath in clean_files:
        if run_script(filepath) != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}")


def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing at {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus directory."

    failed_files = []
    for filepath in evil_files:
        if run_script(filepath) != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}")


def test_generated_logs_at_unpredictable_paths():
    n, window = video_parameters()
    base = 50000

    exact_limit = [
        {"timestamp": base + i, "user_id": "limit-user", "action": "update"}
        for i in range(n)
    ]
    over_limit = [
        {"timestamp": base + i, "user_id": "flood-user", "action": "update"}
        for i in range(n + 1)
    ]
    spaced_events = [
        {"timestamp": base + i * (window + 1), "user_id": "spaced-user", "action": "update"}
        for i in range(n + 1)
    ]
    separate_users = []
    for user in ("alpha", "beta"):
        separate_users.extend(
            {"timestamp": base + i, "user_id": user, "action": "update"}
            for i in range(n)
        )
    out_of_order_flood = list(reversed([
        {"timestamp": base + i, "user_id": "unordered-user", "action": "update"}
        for i in range(n + 1)
    ]))

    cases = [
        (b"", 0),
        (jsonl(exact_limit), 0),
        (jsonl(spaced_events), 0),
        (jsonl(separate_users), 0),
        (b'{"timestamp": 60000, "user_id": "unicode-user", "action": "ok\\u0041"}\n', 0),
        (jsonl(over_limit), 1),
        (jsonl(out_of_order_flood), 1),
        (b'{"timestamp": 70000, "user_id": "m1", "action": "bad\\u12"}\n', 1),
        (b'{"timestamp": 70001, "user_id": "m2", "action": "bad\\u12G4"}\n', 1),
        (b'{"timestamp": 70002, "user_id": "m3", "action": "bad\\u"}\n', 1),
        (b'{"timestamp": 70003, "user_id": "m4", "action": "bad\\u0X00"}\n', 1),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sanitizer-inputs-") as directory:
        failures = []
        for payload, expected in cases:
            filepath = os.path.join(directory, uuid.uuid4().hex)
            with open(filepath, "wb") as handle:
                handle.write(payload)
            actual = run_script(filepath)
            if actual != expected:
                failures.append((expected, actual))

        assert not failures, f"Generated behavioral checks failed (expected/actual): {failures}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
