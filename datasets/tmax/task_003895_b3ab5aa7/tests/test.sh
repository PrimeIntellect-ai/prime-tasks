#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tarfile
import tempfile
import uuid

import cv2
import pytest


def test_backup_archive():
    """Test that the legacy backup archive exists, is valid tar.gz, and contains the config file."""
    backup_path = "/home/user/legacy_backup.tar.gz"
    assert os.path.exists(backup_path), f"Backup archive {backup_path} does not exist."
    assert tarfile.is_tarfile(backup_path), f"File {backup_path} is not a valid tar archive."

    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            names = tar.getnames()
            found = any("legacy_monitor/config.json" in name for name in names)
            assert found, f"Archive does not contain 'legacy_monitor/config.json'. Contents: {names}"
    except tarfile.ReadError:
        pytest.fail(f"Could not read {backup_path} as a gzip-compressed tar archive.")


def test_tunnel_script():
    """Test that the tunnel script contains and actually invokes the required SSH tunnel command."""
    script_path = "/home/user/tunnel.sh"
    assert os.path.exists(script_path), f"Tunnel script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Tunnel script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    pattern = r"ssh.*-L.*9999:remote-telemetry\.internal:80.*deploy@bastion\.internal"
    assert re.search(pattern, content), f"Tunnel script does not contain the correct ssh command. Content: {content}"

    with tempfile.TemporaryDirectory(prefix="tunnel_verify_") as td:
        os.chmod(td, 0o777)
        fake_bin = os.path.join(td, "bin")
        os.mkdir(fake_bin, 0o755)
        capture = os.path.join(td, "calls")
        open(capture, "w").close()
        os.chmod(capture, 0o666)
        fake_ssh = os.path.join(fake_bin, "ssh")
        with open(fake_ssh, "w") as f:
            f.write("#!/bin/sh\n{ printf '%s\\n' '__CALL__'; printf '%s\\n' \"$@\"; } >> \"$SSH_CAPTURE\"\nexit 0\n")
        os.chmod(fake_ssh, 0o755)

        env = os.environ.copy()
        env["PATH"] = fake_bin + ":/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        env["SSH_CAPTURE"] = capture
        result = subprocess.run(
            ["runuser", "-u", "user", "--", script_path],
            env=env,
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert result.returncode == 0, f"Tunnel script failed when executed: {result.stderr}"

        with open(capture) as f:
            lines = [line.rstrip("\n") for line in f]
        calls = []
        for line in lines:
            if line == "__CALL__":
                calls.append([])
            elif calls:
                calls[-1].append(line)

        def valid_call(args):
            destination_ok = "deploy@bastion.internal" in args
            forwarding_ok = "-L9999:remote-telemetry.internal:80" in args
            for i, arg in enumerate(args[:-1]):
                if arg == "-L" and args[i + 1] == "9999:remote-telemetry.internal:80":
                    forwarding_ok = True
            return destination_ok and forwarding_ok

        assert any(valid_call(call) for call in calls), f"Script did not invoke ssh with the required forwarding arguments. Calls: {calls}"


def test_dropped_frames():
    """Recompute the dropped-frame count from the supplied video and check the saved result."""
    frames_path = "/home/user/dropped_frames.txt"
    assert os.path.exists(frames_path), f"Dropped frames file {frames_path} does not exist."

    with open(frames_path, "r") as f:
        content = f.read().strip()

    assert content == "14", f"Expected dropped frames count to be '14', but got '{content}'."

    capture = cv2.VideoCapture("/app/deployment_test_feed.mp4")
    assert capture.isOpened(), "Could not open deployment test video."
    computed = 0
    total = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        total += 1
        height, width = frame.shape[:2]
        blue, green, red = (int(v) for v in frame[height // 2, width // 2])
        # mp4v is lossy, so allow the small codec deviation from the source's
        # exact (255, 0, 0) pixel while preserving the intended classification.
        if blue > 240 and green < 10 and red < 10:
            computed += 1
    capture.release()
    assert total > 0, "Deployment test video contained no decodable frames."
    assert int(content) == computed, f"Saved count {content} does not match the video-derived count {computed}."


def run_sanitizer(sanitizer_path, path):
    return subprocess.run(
        ["python3", sanitizer_path, path],
        capture_output=True,
        timeout=4,
    ).returncode


def test_sanitizer_adversarial_corpus():
    """Test the sanitizer script against the original clean and evil corpora."""
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.exists(sanitizer_path), f"Sanitizer script {sanitizer_path} does not exist."
    assert os.path.isfile(sanitizer_path), f"Sanitizer path {sanitizer_path} is not a regular file."

    clean_dir = "/app/corpora/clean/"
    evil_dir = "/app/corpora/evil/"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}."
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}."

    clean_failures = []
    for cf in clean_files:
        if run_sanitizer(sanitizer_path, cf) != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        if run_sanitizer(sanitizer_path, ef) != 1:
            evil_failures.append(os.path.basename(ef))

    error_msgs = []
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_sanitizer_randomized_neutral_paths():
    """Exercise parsed values using unpredictable files that share one neutral directory."""
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path)

    with tempfile.TemporaryDirectory(prefix="telemetry_cases_") as td:
        cases = []
        for i in range(18):
            token = secrets.token_hex(10)
            payload = {
                "timestamp": f"2026-09-{(i % 28) + 1:02d}T12:34:56Z",
                "locale": ["en_US.UTF-8", "fr_FR.UTF-8", "de_DE.UTF-8"][i % 3],
                "timezone": ["America/New_York", "Europe/Paris", "Asia/Tokyo"][i % 3],
                "metadata": {"device": "camera_" + token, "labels": ["edge", "healthy", token]},
            }
            cases.append((payload, 0))

        attacks = [";", "|", "&", "$(id)", "`id`", "../"]
        for i in range(30):
            token = secrets.token_hex(8)
            attack = attacks[i % len(attacks)]
            payload = {
                "timestamp": "2026-09-11T12:34:56Z",
                "locale": "en_US.UTF-8",
                "timezone": "America/New_York",
                "metadata": {"device": "camera_" + token, "values": ["normal", token]},
            }
            malicious = "prefix_" + token + attack + "suffix_" + secrets.token_hex(4)
            if i % 3 == 0:
                payload["locale"] = malicious
            elif i % 3 == 1:
                payload["timezone"] = malicious
            else:
                payload["metadata"]["values"].append(malicious)
            cases.append((payload, 1))

        # Random names, a common neutral directory, and randomized ordering prevent
        # classification based on clean/evil path components or call position.
        keyed = [(secrets.randbits(128), payload, expected) for payload, expected in cases]
        keyed.sort(key=lambda item: item[0])
        failures = []
        for _, payload, expected in keyed:
            path = os.path.join(td, uuid.uuid4().hex + ".json")
            with open(path, "w") as f:
                json.dump(payload, f)
            actual = run_sanitizer(sanitizer_path, path)
            if actual != expected:
                failures.append((expected, actual, payload))

        assert not failures, f"Sanitizer misclassified {len(failures)} randomized parsed-value cases; first failure: {failures[:1]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
