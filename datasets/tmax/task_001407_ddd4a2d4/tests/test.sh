#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pwd
import re
import secrets
import struct
import subprocess
import tempfile
import wave
import pytest

USER_UID = pwd.getpwnam("user").pw_uid
USER_RUNTIME = f"/run/user/{USER_UID}"
USER_ENV = [
    "env",
    "HOME=/home/user",
    "USER=user",
    "LOGNAME=user",
    f"XDG_RUNTIME_DIR={USER_RUNTIME}",
    f"DBUS_SESSION_BUS_ADDRESS=unix:path={USER_RUNTIME}/bus",
]


def calculate_rms(wav_path):
    with wave.open(wav_path, "rb") as w:
        assert w.getnchannels() == 1
        assert w.getsampwidth() == 2
        n_frames = w.getnframes()
        data = w.readframes(n_frames)
        samples = struct.unpack(f"<{n_frames}h", data)
        return math.sqrt(sum(s ** 2 for s in samples) / n_frames)


def user_command(*args, check=True):
    return subprocess.run(
        ["runuser", "-u", "user", "--", *USER_ENV, *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=check,
        timeout=30,
    )


def systemctl_user(*args, check=True):
    return user_command("systemctl", "--user", *args, check=check)


def test_directories_and_symlink():
    assert os.path.isdir("/home/user/inbox"), "/home/user/inbox directory is missing"
    assert os.path.isdir("/home/user/outbox"), "/home/user/outbox directory is missing"

    symlink_path = "/home/user/inbox/target.wav"
    assert os.path.islink(symlink_path), f"Symlink missing at {symlink_path}"
    assert os.readlink(symlink_path) == "/app/input.wav", f"Symlink {symlink_path} does not point to /app/input.wav"


def test_binary_exists():
    binary_path = "/home/user/bin/analyzer"
    assert os.path.isfile(binary_path), f"Compiled binary missing at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "analyzer is not a compiled ELF executable"


def test_analyzer_on_verifier_generated_audio():
    binary_path = "/home/user/bin/analyzer"
    with tempfile.TemporaryDirectory(prefix="analyzer-verifier-") as td:
        wav_path = os.path.join(td, "challenge.wav")
        output_path = os.path.join(td, "result.txt")

        count = 997 + secrets.randbelow(1000)
        samples = [secrets.randbelow(65536) - 32768 for _ in range(count)]
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(8000 + secrets.randbelow(32000))
            w.writeframes(struct.pack(f"<{count}h", *samples))

        expected = math.sqrt(sum(s ** 2 for s in samples) / count)
        result = subprocess.run(
            [binary_path, wav_path, output_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=20,
        )
        assert result.returncode == 0, f"analyzer failed on generated WAV: {result.stdout}"
        assert os.path.isfile(output_path), "analyzer did not create its requested output file"
        content = open(output_path, "r").read().strip()
        assert re.fullmatch(r"-?\d+\.\d{2}", content), f"analyzer output is not formatted to two decimal places: {content!r}"
        assert content == f"{expected:.2f}", f"analyzer returned {content}, expected {expected:.2f}"


def test_service_file_exists():
    service_path = "/home/user/.config/systemd/user/audio-analyzer.service"
    assert os.path.isfile(service_path), f"Systemd service file missing at {service_path}"


def test_service_executes_pipeline_successfully():
    systemctl_user("daemon-reload")
    exec_start = systemctl_user("show", "audio-analyzer.service", "-p", "ExecStart", "--value").stdout
    assert "/home/user/bin/analyzer" in exec_start, f"service does not execute the analyzer: {exec_start}"
    assert "/home/user/inbox/target.wav" in exec_start, f"service has the wrong input argument: {exec_start}"
    assert "/home/user/outbox/rms.txt" in exec_start, f"service has the wrong output argument: {exec_start}"

    output_path = "/home/user/outbox/rms.txt"
    if os.path.lexists(output_path):
        os.remove(output_path)

    started = systemctl_user("restart", "audio-analyzer.service", check=False)
    assert started.returncode == 0, f"systemd could not start the service:\n{started.stdout}"

    properties = systemctl_user(
        "show", "audio-analyzer.service",
        "-p", "ActiveState", "-p", "SubState", "-p", "Result"
    ).stdout
    parsed = dict(line.split("=", 1) for line in properties.splitlines() if "=" in line)
    assert parsed.get("ActiveState") == "active", f"service did not remain active after completion: {properties}"
    assert parsed.get("SubState") == "exited", f"service is not in its completed/exited state: {properties}"
    assert parsed.get("Result") == "success", f"service did not complete successfully: {properties}"

    status = systemctl_user("status", "audio-analyzer.service", "--no-pager", check=False)
    assert status.returncode == 0, f"systemctl status reports service failure:\n{status.stdout}"
    assert "Active: active" in status.stdout, f"service is not active according to systemctl status:\n{status.stdout}"
    assert os.path.isfile(output_path), "starting the service did not create rms.txt"


def test_health_check_files():
    script_path = "/home/user/health_check.sh"
    log_path = "/home/user/health.log"

    assert os.path.isfile(script_path), f"Health check script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Health check script at {script_path} is not executable"

    script = open(script_path, "r").read()
    assert "systemctl" in script and "--user" in script and "status" in script, "health check does not use systemctl --user status"
    assert "grep" in script, "health check does not use grep"
    assert "awk" in script, "health check does not use awk"

    assert os.path.isfile(log_path), f"Health log missing at {log_path}"
    before = os.path.getsize(log_path)
    result = user_command(script_path, check=False)
    assert result.returncode == 0, f"health check script failed:\n{result.stdout}"
    assert os.path.getsize(log_path) > before, "health check did not append to health.log"

    with open(log_path, "r") as f:
        content = f.read()
    assert "Active:" in content, "Health log does not contain 'Active:' line"
    appended = content[before:]
    assert "Active:" in appended and "active" in appended, f"new health log entry is not the active service status: {appended!r}"


def test_rms_value():
    output_path = "/home/user/outbox/rms.txt"
    assert os.path.isfile(output_path), f"Output file missing at {output_path}"

    with open(output_path, "r") as f:
        content = f.read().strip()

    try:
        agent_rms = float(content)
    except ValueError:
        pytest.fail(f"Could not parse RMS value from {output_path}: '{content}'")

    truth_rms = calculate_rms("/app/input.wav")
    error = abs(agent_rms - truth_rms)
    assert error <= 1.0, f"RMS metric error too high: expected ~{truth_rms:.2f}, got {agent_rms:.2f} (diff: {error:.2f} > 1.0)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
