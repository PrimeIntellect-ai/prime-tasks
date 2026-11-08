#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shlex
import socket
import string
import subprocess
import tempfile
import threading
import time

import pytest


def decode_gray(path):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1",
         "-vf", "scale=160:120,format=gray", "-f", "rawvideo", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"ffmpeg could not decode {path}: {result.stderr.decode(errors='replace')}"
    assert len(result.stdout) == 160 * 120, f"{path} is not a valid 160x120-decodable image"
    return result.stdout


def mean_abs_error(a, b):
    assert len(a) == len(b)
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def test_symlink_and_frames():
    """Verify symlink and genuine one-frame-per-second extraction."""
    symlink_path = "/home/user/active_feed.mp4"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink"
    assert os.readlink(symlink_path) == "/app/camera1.mp4", f"{symlink_path} does not point to /app/camera1.mp4"

    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), f"Directory {frames_dir} does not exist"

    # Preserve the original filename/count assertions.
    frames = [f for f in os.listdir(frames_dir) if f.startswith("frame_") and f.endswith(".jpg")]
    assert len(frames) == 15, f"Expected 15 frames, found {len(frames)}"
    for i in range(1, 16):
        expected_frame = f"frame_{i:04d}.jpg"
        assert expected_frame in frames, f"Missing {expected_frame}"

    # Derive reference frames from the supplied video at verification time.
    with tempfile.TemporaryDirectory() as reference_dir:
        pattern = os.path.join(reference_dir, "frame_%04d.jpg")
        result = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", "/app/camera1.mp4", "-vf", "fps=1", pattern],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert result.returncode == 0, f"Could not derive reference frames: {result.stderr.decode(errors='replace')}"
        reference_paths = [os.path.join(reference_dir, f"frame_{i:04d}.jpg") for i in range(1, 16)]
        assert all(os.path.isfile(p) for p in reference_paths), "Reference extraction did not produce 15 frames"
        references = [decode_gray(p) for p in reference_paths]

        for i in range(15):
            submitted_path = os.path.join(frames_dir, f"frame_{i + 1:04d}.jpg")
            assert os.path.isfile(submitted_path), f"{submitted_path} is not a regular file"
            assert os.path.getsize(submitted_path) > 0, f"{submitted_path} is empty"
            submitted = decode_gray(submitted_path)
            distances = [mean_abs_error(submitted, ref) for ref in references]
            assert distances[i] <= 20.0, f"{submitted_path} does not visually match the source video"
            assert distances[i] <= min(distances) + 1.0, f"{submitted_path} is not the frame for second {i}"


def test_port_forwarding():
    """Verify socat port forwarding from 8080 to 9090."""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind(('127.0.0.1', 9090))
        server.listen(1)
    except Exception as e:
        pytest.fail(f"Could not bind to 9090 for testing: {e}")

    success = False

    def handle_client():
        nonlocal success
        try:
            server.settimeout(2.0)
            conn, addr = server.accept()
            data = conn.recv(1024)
            if data == b"ping":
                conn.sendall(b"pong")
                success = True
            conn.close()
        except Exception:
            pass

    t = threading.Thread(target=handle_client)
    t.start()
    time.sleep(0.5)

    try:
        client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client.settimeout(2.0)
        client.connect(('127.0.0.1', 8080))
        client.sendall(b"ping")
        resp = client.recv(1024)
        assert resp == b"pong", "Did not receive correct response through port forward"
        client.close()
    except Exception as e:
        pytest.fail(f"Port forwarding test failed: {e}")
    finally:
        server.close()
        t.join(timeout=2)
        assert success, "Dummy server on 9090 did not receive the forwarded request"


def read_bytes(path):
    if not os.path.exists(path):
        return b""
    with open(path, "rb") as f:
        return f.read()


def run_and_check_log(script, raw, expected_code, expected_log):
    logs_dir = "/home/user/logs"
    valid_path = os.path.join(logs_dir, "valid.log")
    rejected_path = os.path.join(logs_dir, "rejected.log")
    before_valid = read_bytes(valid_path)
    before_rejected = read_bytes(rejected_path)

    result = subprocess.run(
        ["python3", script],
        input=raw,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == expected_code, (
        f"Validator returned {result.returncode}, expected {expected_code}, for input {raw!r}"
    )

    after_valid = read_bytes(valid_path)
    after_rejected = read_bytes(rejected_path)
    if expected_log == "valid":
        assert after_valid == before_valid + raw, "Accepted payload was not appended raw to valid.log"
        assert after_rejected == before_rejected, "Accepted payload modified rejected.log"
    else:
        assert after_rejected == before_rejected + raw, "Rejected payload was not appended raw to rejected.log"
        assert after_valid == before_valid, "Rejected payload modified valid.log"


def test_validator_generated_inputs_and_logging():
    """Exercise generated payloads and verify exact raw logging behavior."""
    script = "/home/user/validator.py"
    assert os.path.isfile(script), f"Missing validator script at {script}"
    assert os.path.isdir("/home/user/logs"), "Missing /home/user/logs directory"

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = string.ascii_letters + string.digits

    accepted = []
    for _ in range(8):
        device = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 20)))
        if rng.choice([True, False]):
            tz = "".join(rng.choice(string.ascii_letters + "_") for _ in range(rng.randint(1, 12)))
        else:
            left = "".join(rng.choice(string.ascii_letters + "_") for _ in range(rng.randint(1, 10)))
            right = "".join(rng.choice(string.ascii_letters + "_") for _ in range(rng.randint(1, 10)))
            tz = left + "/" + right
        obj = {"action": "capture", "device_id": device, "tz": tz}
        accepted.append((json.dumps(obj, separators=(", ", ": ")) + "\n").encode())

    bad_device = "cam" + rng.choice([";", "&", "|", "$", "`", " "]) + "x"
    rejected_objects = [
        {"action": "delete", "device_id": "cam1", "tz": "UTC"},
        {"action": "CAPTURE", "device_id": "cam1", "tz": "UTC"},
        {"action": "capture", "device_id": "", "tz": "UTC"},
        {"action": "capture", "device_id": "A" * 21, "tz": "UTC"},
        {"action": "capture", "device_id": bad_device, "tz": "UTC"},
        {"action": "capture", "device_id": "cam-1", "tz": "UTC"},
        {"action": "capture", "device_id": "cam1", "tz": "../UTC"},
        {"action": "capture", "device_id": "cam1", "tz": "America/New_York/Extra"},
        {"action": "capture", "device_id": "cam1", "tz": "America/../UTC"},
        {"action": "capture", "device_id": "cam1", "tz": "GMT+2"},
        {"action": "capture", "device_id": "cam1"},
        {"action": "capture", "device_id": 123, "tz": "UTC"},
    ]
    rejected = [(json.dumps(obj) + "\n").encode() for obj in rejected_objects]
    rejected.extend([b"{not valid json}\n", b"[]\n", b"null\n"])

    for raw in accepted:
        run_and_check_log(script, raw, 0, "valid")
    for raw in rejected:
        run_and_check_log(script, raw, 1, "rejected")


def test_validator_script_adversarial():
    """Preserve the original corpus checks."""
    script = "/home/user/validator.py"
    assert os.path.isfile(script), f"Missing validator script at {script}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = os.listdir(clean_dir)
    evil_files = os.listdir(evil_dir)

    clean_failed = []
    for f in clean_files:
        path = os.path.join(clean_dir, f)
        with open(path, 'rb') as fp:
            res = subprocess.run(["python3", script], stdin=fp, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if res.returncode != 0:
                clean_failed.append(f)

    evil_failed = []
    for f in evil_files:
        path = os.path.join(evil_dir, f)
        with open(path, 'rb') as fp:
            res = subprocess.run(["python3", script], stdin=fp, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if res.returncode == 0:
                evil_failed.append(f)

    if clean_failed or evil_failed:
        msg = []
        if clean_failed:
            msg.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
        if evil_failed:
            msg.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
        pytest.fail(" | ".join(msg))


def test_logrotate_config():
    """Verify and parse the logrotate configuration."""
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"Missing logrotate.conf at {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "daily" in content, "Missing 'daily' rotation in logrotate.conf"
    assert "rotate 7" in content, "Missing 'rotate 7' in logrotate.conf"
    assert "compress" in content, "Missing 'compress' in logrotate.conf"
    assert "create 0644" in content or "create 644" in content, "Missing 'create 0644' in logrotate.conf"
    assert "/home/user/logs" in content, "Log path /home/user/logs is not properly specified in logrotate.conf"

    # Strip comments and parse the block that actually targets every .log file.
    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    blocks = re.findall(r"([^{}]+)\{([^{}]*)\}", uncommented, flags=re.S)
    target_body = None
    for header, body in blocks:
        try:
            paths = shlex.split(header)
        except ValueError as exc:
            pytest.fail(f"Invalid logrotate path syntax: {exc}")
        if "/home/user/logs/*.log" in paths:
            target_body = body
            break
    assert target_body is not None, "No logrotate block targets /home/user/logs/*.log"

    directives = []
    for line in target_body.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            tokens = shlex.split(line)
        except ValueError as exc:
            pytest.fail(f"Invalid logrotate directive syntax: {exc}")
        if tokens:
            directives.append(tokens)

    names = [tokens[0] for tokens in directives]
    assert "daily" in names, "The /home/user/logs/*.log block is not daily"
    assert not any(x in names for x in ("hourly", "weekly", "monthly", "yearly")), "Conflicting rotation frequency"

    rotate_values = [tokens[1] for tokens in directives if tokens[0] == "rotate" and len(tokens) >= 2]
    assert rotate_values and rotate_values[-1] == "7", "The target block must retain exactly 7 rotations"

    compression = None
    creation = None
    for tokens in directives:
        if tokens[0] == "compress":
            compression = True
        elif tokens[0] == "nocompress":
            compression = False
        elif tokens[0] == "create":
            creation = tokens[1] if len(tokens) >= 2 else None
        elif tokens[0] == "nocreate":
            creation = None
    assert compression is True, "Compression is not enabled for the target logs"
    assert creation in ("0644", "644"), "New target log files must be created with mode 0644"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
