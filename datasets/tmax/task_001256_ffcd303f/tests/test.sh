#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import tempfile

import cv2
import pytest


def test_red_alert_count():
    """Verify both the known result and a result derived from the supplied video."""
    count_file = "/home/user/red_alert_count.txt"
    video_path = "/app/server_monitor.mp4"
    assert os.path.exists(count_file), f"Expected output file {count_file} is missing."
    assert os.path.isfile(video_path), f"Expected input video {video_path} is missing."

    with open(count_file, "r") as f:
        content = f.read().strip()

    # Preserve the original assertion.
    assert content == "12", f"Expected red alert count to be '12', but found '{content}'."

    capture = cv2.VideoCapture(video_path)
    assert capture.isOpened(), f"Could not decode {video_path}."
    fps = capture.get(cv2.CAP_PROP_FPS)
    assert fps > 0, f"Invalid frame rate reported for {video_path}: {fps}"

    derived_count = 0
    frame_index = 0
    next_sample_time = 0.0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        frame_time = frame_index / fps
        if frame_time + 1e-9 >= next_sample_time:
            blue, green, red = frame.mean(axis=(0, 1))
            if red > 150 and green < 50 and blue < 50:
                derived_count += 1
            next_sample_time += 1.0
        frame_index += 1
    capture.release()

    assert frame_index > 0, f"No frames were decoded from {video_path}."
    assert content == str(derived_count), (
        f"Red alert count '{content}' does not match the count derived from the video "
        f"('{derived_count}')."
    )


def test_validate_configs_adversarial_corpus():
    """Verify that the validator rejects the original evil corpus and accepts the clean corpus."""
    script_path = "/home/user/validate_configs.sh"
    assert os.path.exists(script_path), f"Validation script {script_path} is missing."
    assert os.path.isfile(script_path), f"Validation script {script_path} is not a file."

    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"

    assert os.path.exists(evil_dir), f"Evil corpus directory {evil_dir} is missing."
    assert os.path.exists(clean_dir), f"Clean corpus directory {clean_dir} is missing."

    evil_files = sorted([os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))])
    clean_files = sorted([os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))])

    evil_bypassed = []
    for fpath in evil_files:
        result = subprocess.run(["bash", script_path, fpath], capture_output=True, timeout=10)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(fpath))

    clean_rejected = []
    for fpath in clean_files:
        result = subprocess.run(["bash", script_path, fpath], capture_output=True, timeout=10)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(fpath))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")

    assert not errors, " | ".join(errors)


def test_validate_configs_generated_same_path_cases():
    """Exercise changing, randomized content at one path so path-based answers cannot pass."""
    script_path = "/home/user/validate_configs.sh"
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(script_path), f"Validation script {script_path} is missing or not a file."

    before_lines = []
    if os.path.exists(log_path):
        with open(log_path, "r", encoding="utf-8", errors="replace") as f:
            before_lines = f.read().splitlines()

    temp_dir = tempfile.mkdtemp(prefix="config-validation-", dir="/home/user")
    config_path = os.path.join(temp_dir, secrets.token_hex(12) + ".conf")
    key_a = "KEY_" + secrets.token_hex(6).upper()
    key_b = "OTHER_" + secrets.token_hex(6).upper()
    value = secrets.token_hex(10)

    clean_one = f"{key_a}={value}\n{key_b}=日本語-{secrets.token_hex(3)}.txt\n# Comment\n"
    clean_two = f"{key_a}=Alpha_42-{secrets.token_hex(4)}\n{key_b}=Español,中文.\n"
    cases = [
        (clean_one, 0, "ACCEPTED"),
        (f"{key_a}={value}\n{key_a}=second{secrets.token_hex(2)}\n", 1, "REJECTED"),
        (f"{key_a}=safe\u200bhidden{secrets.token_hex(2)}\n", 1, "REJECTED"),
        (f"{key_a}=safe\u202ehidden{secrets.token_hex(2)}\n", 1, "REJECTED"),
        (f"{key_a}=safe\u202dhidden{secrets.token_hex(2)}\n", 1, "REJECTED"),
        (f"{key_a}=$(printf {secrets.token_hex(3)})\n", 1, "REJECTED"),
        (f"{key_a}=`printf {secrets.token_hex(3)}`\n", 1, "REJECTED"),
        (clean_two, 0, "ACCEPTED"),
    ]
    random.SystemRandom().shuffle(cases)

    expected_statuses = []
    for content, expected_code, expected_status in cases:
        with open(config_path, "w", encoding="utf-8") as f:
            f.write(content)
        result = subprocess.run(
            ["bash", script_path, config_path], capture_output=True, timeout=10
        )
        assert result.returncode == expected_code, (
            f"Validator returned {result.returncode}, expected {expected_code}, for a "
            f"randomized {expected_status.lower()} configuration at {config_path}. "
            f"stderr={result.stderr.decode(errors='replace')!r}"
        )
        expected_statuses.append(expected_status)

    assert os.path.exists(log_path), f"Log file {log_path} is missing after validation calls."
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        after_lines = f.read().splitlines()

    added_lines = after_lines[len(before_lines):]
    assert len(added_lines) == len(cases), (
        f"Expected exactly {len(cases)} new log entries, found {len(added_lines)}."
    )
    file_pattern = f"(?:{re.escape(config_path)}|{re.escape(os.path.basename(config_path))})"
    for line, expected_status in zip(added_lines, expected_statuses):
        assert re.fullmatch(
            rf"\[[^\]\r\n]+\] FILE={file_pattern} STATUS={expected_status}", line
        ), f"Incorrect log entry for generated case: {line!r}"


def test_pipeline_log_format():
    """Verify that the pipeline log exists and contains correctly formatted entries."""
    log_path = "/home/user/pipeline.log"
    assert os.path.exists(log_path), f"Log file {log_path} is missing."

    with open(log_path, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) > 0, "Log file is empty."

    # Preserve the original checks on the last few generated entries.
    for line in lines[-5:]:
        assert "FILE=" in line, f"Log entry missing 'FILE=': {line}"
        assert "STATUS=ACCEPTED" in line or "STATUS=REJECTED" in line, f"Log entry missing correct 'STATUS=': {line}"
        assert line.startswith("["), f"Log entry does not start with timestamp: {line}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
