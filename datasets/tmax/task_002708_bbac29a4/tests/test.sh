#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import string
import subprocess

import cv2
import numpy as np

VIDEO_PATH = "/app/server_status.mp4"
AGENT_PATH = "/home/user/log_filter"


def exact_red_frame_count():
    assert os.path.isfile(VIDEO_PATH), f"Missing video at {VIDEO_PATH}"
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open video at {VIDEO_PATH}"

    count = 0
    decoded = 0
    target_bgr = np.array([0, 0, 255], dtype=np.uint8)
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            decoded += 1
            if frame.ndim == 3 and frame.shape[2] == 3 and np.all(frame == target_bgr):
                count += 1
    finally:
        cap.release()

    assert decoded > 0, "Video contained no decodable frames"
    return count


def run_agent(test_input):
    proc = subprocess.run(
        [AGENT_PATH],
        input=test_input,
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert proc.returncode == 0, (
        f"Agent exited with status {proc.returncode} for input {test_input!r}. "
        f"stderr: {proc.stderr!r}"
    )
    return proc.stdout


def expected_output(test_input, threshold):
    return "ALERT\n" if test_input.count("ERROR") > threshold else "OK\n"


def test_log_file_created():
    log_path = "/var/log/health.log"
    assert os.path.isfile(log_path), f"Missing dummy log file at {log_path}"
    assert not os.path.islink(log_path), f"Log path {log_path} must be a regular file"

    info = os.stat(log_path)
    mode = stat.S_IMODE(info.st_mode)
    assert stat.S_ISREG(info.st_mode), f"Log path {log_path} is not a regular file"
    assert mode & 0o600 == 0o600, "Log owner must have read and write permission"
    assert mode & 0o022 == 0, "Log file must not be writable by group or others"
    assert mode & 0o111 == 0, "Log file must not be executable"


def test_logrotate_config():
    config_path = "/etc/logrotate.d/health_monitor"
    assert os.path.isfile(config_path), f"Missing logrotate config at {config_path}"
    assert not os.path.islink(config_path), f"Logrotate config {config_path} must be a regular file"

    info = os.stat(config_path)
    mode = stat.S_IMODE(info.st_mode)
    assert mode & 0o022 == 0, "Logrotate config must not be writable by group or others"

    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original required checks.
    assert "/var/log/health.log" in content, "Logrotate config does not specify /var/log/health.log"
    assert "daily" in content, "Logrotate config missing 'daily' directive"
    assert "rotate 7" in content, "Logrotate config missing 'rotate 7' directive"
    assert "compress" in content, "Logrotate config missing 'compress' directive"

    # Check that the directives are active and scoped to the requested log.
    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    block_match = re.search(
        r'(?ms)^[^\n{]*(?:"/var/log/health\.log"|\'/var/log/health\.log\'|/var/log/health\.log)[^\n{]*\n?\s*\{(.*?)^\s*\}',
        uncommented,
    )
    assert block_match, "No logrotate block actively targets /var/log/health.log"

    directives = []
    for line in block_match.group(1).splitlines():
        tokens = line.strip().split()
        if tokens:
            directives.append(tokens)

    assert any(tokens == ["daily"] for tokens in directives), "The health log block is not configured daily"
    assert any(tokens == ["rotate", "7"] for tokens in directives), "The health log block does not keep 7 backups"
    assert any(tokens == ["compress"] for tokens in directives), "The health log block does not enable compression"

    syntax = subprocess.run(
        ["logrotate", "--debug", config_path],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert syntax.returncode == 0, (
        "Logrotate rejected the configuration.\n"
        f"stdout: {syntax.stdout}\nstderr: {syntax.stderr}"
    )


def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Missing script at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Script at {AGENT_PATH} is not executable"


def test_fuzz_equivalence_to_video_derived_threshold():
    threshold = exact_red_frame_count()

    boundary_inputs = [
        "",
        "ERROR" * threshold,
        "ERROR" * (threshold + 1),
        "prefix ERROR suffix",
        "ERRORERROR",
        "error Error ERRO R",
        "\nERROR\n" * (threshold + 2),
    ]

    random.seed(42)
    inputs = list(boundary_inputs)
    alphabet = string.ascii_letters + string.digits + " _-\n"
    for _ in range(500):
        base_len = random.randint(0, 200)
        value = "".join(random.choices(alphabet, k=base_len))
        for _ in range(random.randint(0, 10)):
            insert_pos = random.randint(0, len(value))
            value = value[:insert_pos] + "ERROR" + value[insert_pos:]
        inputs.append(value)

    for i, test_input in enumerate(inputs):
        actual = run_agent(test_input)
        expected = expected_output(test_input, threshold)
        assert actual == expected, (
            f"Mismatch on iteration {i}.\n"
            f"Input: {test_input!r}\n"
            f"Expected: {expected!r}\n"
            f"Agent output: {actual!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
