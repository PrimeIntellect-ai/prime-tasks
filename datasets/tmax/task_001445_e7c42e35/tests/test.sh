#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile

import cv2


def test_stage1_makefile_fixed_and_compiled():
    """Verify that the Makefile was fixed and libjit.so builds as a shared library."""
    makefile_path = "/home/user/libjit/Makefile"
    assert os.path.isfile(makefile_path), "Makefile is missing."

    with open(makefile_path, "r") as f:
        makefile_content = f.read()

    assert "-fPIC" in makefile_content, "Makefile does not include -fPIC flag."
    assert "-shared" in makefile_content, "Makefile does not include -shared flag."

    build_result = subprocess.run(
        ["make", "-C", "/home/user/libjit"], capture_output=True, text=True
    )
    assert build_result.returncode == 0, f"make failed: {build_result.stderr}"

    so_path = "/home/user/libjit/libjit.so"
    assert os.path.isfile(so_path), "libjit.so was not generated."

    file_cmd = subprocess.run(["file", so_path], capture_output=True, text=True)
    assert "shared object" in file_cmd.stdout, (
        f"libjit.so is not a shared object: {file_cmd.stdout}"
    )


def test_stage2_red_frames_extracted():
    """Decode the supplied video and compare the submitted frame list to its pixels."""
    video_path = "/app/ci_run.mp4"
    output_path = "/home/user/red_frames.txt"
    assert os.path.isfile(video_path), "ci_run.mp4 is missing."
    assert os.path.isfile(output_path), "red_frames.txt is missing."

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    capture = cv2.VideoCapture(video_path)
    assert capture.isOpened(), "Could not decode ci_run.mp4."

    expected = []
    frame_index = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        assert frame is not None and frame.shape[0] > 0 and frame.shape[1] > 0
        # OpenCV returns BGR, so pure RGB red is BGR (0, 0, 255).
        if tuple(int(value) for value in frame[0, 0]) == (0, 0, 255):
            expected.append(str(frame_index))
        frame_index += 1
    capture.release()

    assert frame_index > 0, "No frames could be decoded from ci_run.mp4."
    assert lines == expected, f"Expected red frames {expected}, but got {lines}."


def run_sanitizer(sanitizer_path, payload_path):
    return subprocess.run(
        ["python3", sanitizer_path, payload_path], capture_output=True, text=True
    )


def payload_is_evil(payload):
    return any(marker in payload for marker in (b"\x0f\x05", b"\x0f\x34", b"\xcd\x80"))


def assert_classification(sanitizer_path, payload_path, expected_evil):
    result = run_sanitizer(sanitizer_path, payload_path)
    expected_code = 1 if expected_evil else 0
    expected_output = "EVIL" if expected_evil else "CLEAN"
    assert result.returncode == expected_code and result.stdout.strip() == expected_output, (
        f"Incorrect classification for {payload_path}: expected "
        f"{expected_output}/{expected_code}, got {result.stdout!r}/{result.returncode}; "
        f"stderr={result.stderr!r}"
    )


def test_stage3_sanitizer_adversarial_corpus():
    """Test both the shipped corpus and generated payloads at unrelated paths."""
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), "sanitizer.py is missing."

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".json")]
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".json")]
    assert evil_files, "The evil corpus is empty."
    assert clean_files, "The clean corpus is empty."

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        full_path = os.path.join(evil_dir, evil_file)
        result = run_sanitizer(sanitizer_path, full_path)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            evil_bypassed.append(evil_file)

    for clean_file in clean_files:
        full_path = os.path.join(clean_dir, clean_file)
        result = run_sanitizer(sanitizer_path, full_path)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            clean_modified.append(clean_file)

    error_msg = []
    if evil_bypassed:
        error_msg.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        error_msg.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified: "
            + ", ".join(clean_modified)
        )
    assert not evil_bypassed and not clean_modified, " | ".join(error_msg)

    generated = [
        b"",
        b"\x0f",
        b"\x05\x0f",
        b"\xcd\x7f\x80",
        b"\x90\x0f\x05",
        b"\x0f\x34\xc3",
        b"\x90\xcd\x80\x90",
        b"\x0f\x05\x0f\x34\xcd\x80",
    ]

    # Generate fresh payloads so correctness cannot be inferred from corpus paths.
    for _ in range(24):
        candidate = os.urandom(secrets.randbelow(48) + 1)
        generated.append(candidate)

    markers = (b"\x0f\x05", b"\x0f\x34", b"\xcd\x80")
    for marker in markers:
        for _ in range(8):
            prefix = os.urandom(secrets.randbelow(24))
            suffix = os.urandom(secrets.randbelow(24))
            generated.append(prefix + marker + suffix)

    secrets.SystemRandom().shuffle(generated)
    with tempfile.TemporaryDirectory(prefix="payload-check-") as temp_dir:
        for payload in generated:
            path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
            with open(path, "w") as f:
                json.dump({"payload": payload.hex()}, f)
            assert_classification(sanitizer_path, path, payload_is_evil(payload))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
