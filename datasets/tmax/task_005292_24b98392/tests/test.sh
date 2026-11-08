#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import struct
import subprocess

import pytest

SANITIZER = "/home/user/sanitizer.sh"


def recover_frame_from_wal(path):
    with open(path, "rb") as f:
        data = f.read()

    recovered = []
    for pos in range(0, max(0, len(data) - 5)):
        if data[pos] == 0xAA and data[pos + 5] == 0xBB:
            value = struct.unpack(">f", data[pos + 1:pos + 5])[0]
            if math.isfinite(value):
                repaired = round(value)
                assert abs(value - repaired) < 0.01, (
                    f"WAL frame value {value!r} cannot be repaired to an integer"
                )
                recovered.append(repaired)

    assert recovered, "No valid AA...BB frame entries found in the WAL"
    return recovered[-1]


def run_sanitizer(payload):
    try:
        return subprocess.run(
            [SANITIZER], input=payload, capture_output=True, timeout=3
        )
    except subprocess.TimeoutExpired:
        pytest.fail("sanitizer timed out on a metadata payload")


def test_crash_frame_recovered():
    crash_frame_path = "/home/user/crash_frame.txt"
    assert os.path.isfile(crash_frame_path), f"Missing {crash_frame_path}"

    with open(crash_frame_path, "r") as f:
        content = f.read().strip()

    # Preserve the original expected-state assertion and independently derive it
    # from the supplied WAL so corruption or replacement of the WAL is detected.
    assert content == "845", f"Expected crash frame to be '845', but got '{content}'"
    expected = recover_frame_from_wal("/home/user/service/state.wal")
    assert expected == 845, f"The supplied WAL was unexpectedly modified (decoded {expected})"
    assert re.fullmatch(r"[0-9]+", content), "crash_frame.txt must contain one integer"
    assert int(content) == expected


def test_video_frames_were_extracted():
    image_extensions = {".png", ".jpg", ".jpeg", ".bmp", ".webp", ".ppm", ".pgm"}
    candidates = []
    for root in ("/home/user", "/app", "/tmp"):
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if not d.startswith(".")]
            for name in files:
                if os.path.splitext(name)[1].lower() in image_extensions:
                    candidates.append(os.path.join(directory, name))
            if len(candidates) >= 200:
                break

    valid_frames = []
    for path in candidates[:200]:
        probe = subprocess.run(
            [
                "ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_entries", "stream=width,height", "-of", "csv=p=0",
                path,
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if probe.returncode == 0:
            match = re.fullmatch(r"\s*(\d+),(\d+)\s*", probe.stdout)
            if match and int(match.group(1)) == 128 and int(match.group(2)) == 128:
                valid_frames.append(path)

    assert len(valid_frames) >= 2, (
        "Expected at least two ffmpeg-extracted 128x128 video frames under "
        "/home/user, /app, or /tmp"
    )


def test_sanitizer_executable():
    assert os.path.isfile(SANITIZER), f"Missing {SANITIZER}"
    assert os.access(SANITIZER, os.X_OK), f"Script {SANITIZER} is not executable"
    with open(SANITIZER, "rb") as f:
        first_line = f.readline(256).decode("utf-8", "replace").strip()
    assert first_line in ("#!/bin/bash", "#!/usr/bin/bash", "#!/usr/bin/env bash"), (
        "sanitizer.sh must be a Bash script"
    )


def test_sanitizer_adversarial_corpus():
    evil_dir = "/home/user/metadata/evil/"
    clean_dir = "/home/user/metadata/clean/"

    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "Evil corpus is empty"
    assert len(clean_files) > 0, "Clean corpus is empty"

    evil_bypassed = []
    clean_modified_or_failed = []

    for evil_file in evil_files:
        with open(evil_file, "rb") as f:
            payload = f.read()
        result = run_sanitizer(payload)
        if result.returncode != 1:
            evil_bypassed.append((os.path.basename(evil_file), result.returncode))

    for clean_file in clean_files:
        with open(clean_file, "rb") as f:
            payload = f.read()
        result = run_sanitizer(payload)
        if result.returncode != 0 or result.stdout != payload:
            clean_modified_or_failed.append((os.path.basename(clean_file), result.returncode))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {evil_bypassed[:5]}")
    if clean_modified_or_failed:
        error_msgs.append(f"{len(clean_modified_or_failed)} of {len(clean_files)} clean modified or failed: {clean_modified_or_failed[:5]}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_sanitizer_randomized_equal_length_payloads():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))

    for case in range(24):
        timestamp = rng.randrange(1, 10**12)
        bbox = [rng.randrange(-5000, 5001) for _ in range(4)]
        nonce = secrets.token_hex(rng.randrange(4, 18))
        depth = rng.randrange(7, 13)

        nested = bbox
        for _ in range(depth):
            nested = {"bbox": nested}

        evil_obj = {
            "timestamp": timestamp,
            "camera": rng.randrange(1, 10000),
            "nonce": nonce,
            "bbox": nested,
        }
        evil = json.dumps(evil_obj, separators=(",", ":"), sort_keys=False).encode() + b"\n"

        clean_obj = {
            "timestamp": timestamp,
            "camera": rng.randrange(1, 10000),
            "nonce": secrets.token_hex(rng.randrange(4, 18)),
            "bbox": bbox,
            "padding": "",
        }
        clean = json.dumps(clean_obj, separators=(",", ":"), sort_keys=False).encode() + b"\n"
        if len(clean) < len(evil):
            clean_obj["padding"] = "x" * (len(evil) - len(clean))
            clean = json.dumps(clean_obj, separators=(",", ":"), sort_keys=False).encode() + b"\n"

        # Equal-length pairs prevent classification by payload length.
        assert len(clean) == len(evil)

        clean_result = run_sanitizer(clean)
        assert clean_result.returncode == 0, (
            f"random clean payload {case} exited {clean_result.returncode}"
        )
        assert clean_result.stdout == clean, f"random clean payload {case} was modified"

        evil_result = run_sanitizer(evil)
        assert evil_result.returncode == 1, (
            f"random malicious nested payload {case} exited {evil_result.returncode}"
        )

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
