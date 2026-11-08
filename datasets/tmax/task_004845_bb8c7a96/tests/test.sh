#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess
import tempfile

import cv2


def output_matches_input(path, stdout):
    with open(path, "r") as f:
        expected_content = f.read().strip()

    if expected_content in stdout.strip():
        return True

    try:
        return json.loads(expected_content) == json.loads(stdout.strip())
    except (json.JSONDecodeError, TypeError):
        return False


def test_adversarial_corpus_sanitize():
    script_path = "/home/user/sanitize.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for cf in clean_files:
        result = subprocess.run(["python3", script_path, cf], capture_output=True, text=True)
        if result.returncode != 0 or not output_matches_input(cf, result.stdout):
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        result = subprocess.run(["python3", script_path, ef], capture_output=True, text=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(ef))

    error_messages = []
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")

    assert not error_messages, " | ".join(error_messages)


def test_randomized_sanitizer_inputs():
    script_path = "/home/user/sanitize.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    nonce = secrets.token_hex(16)
    cases = [
        ({"post_install_script": f"echo safe-{nonce}"}, False),
        ({"post_install_script": "python3 -V", "tag": nonce}, False),
        ({"post_install_script": "", "tag": nonce}, False),
        ({"tag": nonce, "description": "wget curl nc /dev/tcp mkfifo"}, False),
        ({"post_install_script": f"echo safe-{nonce}", "other": "curl"}, False),
        ({"post_install_script": f"prefix-wget-{nonce}"}, True),
        ({"post_install_script": f"prefix-curl-{nonce}"}, True),
        ({"post_install_script": f"prefix-nc-{nonce}"}, True),
        ({"post_install_script": f"prefix-/dev/tcp-{nonce}"}, True),
        ({"post_install_script": f"prefix-mkfifo-{nonce}"}, True),
        ({"post_install_script": f"echo {nonce}; curl example.invalid; echo done"}, True),
    ]
    secrets.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix=f"cfg-{secrets.token_hex(12)}-") as temp_dir:
        for data, should_reject in cases:
            path = os.path.join(temp_dir, secrets.token_hex(16) + ".json")
            raw = json.dumps(data, separators=(",", ":")) + "\n"
            with open(path, "w") as f:
                f.write(raw)

            result = subprocess.run(["python3", script_path, path], capture_output=True, text=True)
            expected_code = 1 if should_reject else 0
            if result.returncode != expected_code:
                failures.append(f"wrong exit status for {os.path.basename(path)}")
            elif not should_reject and not output_matches_input(path, result.stdout):
                failures.append(f"safe input not printed for {os.path.basename(path)}")

    assert not failures, "; ".join(failures)


def count_red_center_frames(video_path):
    capture = cv2.VideoCapture(video_path)
    assert capture.isOpened(), f"Could not open video {video_path}."

    count = 0
    decoded = 0
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            decoded += 1
            height, width = frame.shape[:2]
            blue, green, red = [int(v) for v in frame[height // 2, width // 2]]
            if red > 200 and green < 50 and blue < 50:
                count += 1
    finally:
        capture.release()

    assert decoded > 0, f"No frames decoded from {video_path}."
    return count


def test_led_flashes_count():
    output_file = "/home/user/led_flashes.txt"
    video_file = "/app/boot_sequence.mp4"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(video_file), f"Video file {video_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip()

    expected = count_red_center_frames(video_file)
    assert content == str(expected), (
        f"Expected led_flashes.txt to contain '{expected}', but got '{content}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
