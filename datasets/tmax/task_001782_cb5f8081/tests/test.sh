#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
import wave

import pytest

BINARY = "/home/user/audio_filter/target/release/audio_filter"
PROJECT = "/home/user/audio_filter"
EXPECTED_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"


def read_crontab():
    try:
        return subprocess.check_output(
            ["crontab", "-l", "-u", "user"],
            stderr=subprocess.STDOUT,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to read crontab for user 'user'. Output: {e.output}")


def test_cron_fixed():
    """Verify that the crontab for 'user' has been updated with required env vars."""
    output = read_crontab()
    assert "LOG_DIR=/home/user/logs" in output, "crontab is missing LOG_DIR=/home/user/logs"
    assert f"PATH={EXPECTED_PATH}" in output, "crontab is missing the required PATH"


def test_cron_command_runs_in_cron_environment():
    """Run the actual every-minute cron command with its configured environment."""
    output = read_crontab()
    lines = [line.strip() for line in output.splitlines() if line.strip() and not line.lstrip().startswith("#")]

    assert any(re.fullmatch(r"LOG_DIR\s*=\s*/home/user/logs", line) for line in lines), \
        "LOG_DIR must be an active crontab environment assignment"
    assert any(re.fullmatch(rf"PATH\s*=\s*{re.escape(EXPECTED_PATH)}", line) for line in lines), \
        "PATH must be an active crontab environment assignment"

    commands = []
    for line in lines:
        parts = line.split(None, 5)
        if len(parts) == 6 and parts[:5] == ["*", "*", "*", "*", "*"]:
            if "/home/user/scripts/health_check.sh" in parts[5]:
                commands.append(parts[5])
    assert commands, "health_check.sh is not scheduled every minute"

    log_path = "/home/user/logs/health.log"
    if os.path.lexists(log_path):
        if os.path.isdir(log_path) and not os.path.islink(log_path):
            shutil.rmtree(log_path)
        else:
            os.unlink(log_path)

    result = subprocess.run(
        [
            "runuser", "-u", "user", "--", "env", "-i",
            "LOG_DIR=/home/user/logs",
            f"PATH={EXPECTED_PATH}",
            "HOME=/home/user", "USER=user", "LOGNAME=user", "SHELL=/bin/sh",
            "/bin/sh", "-c", commands[0],
        ],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, \
        f"scheduled health command failed in cron environment: {result.stdout}{result.stderr}"
    assert os.path.isfile(log_path), "scheduled health command did not create /home/user/logs/health.log"
    with open(log_path, "r", errors="replace") as f:
        contents = f.read()
    assert "Health check passed" in contents, "health check did not write its success result to health.log"


def test_rust_project_builds_release_binary():
    """Require a Rust/Cargo project and rebuild the submitted release executable."""
    manifest = os.path.join(PROJECT, "Cargo.toml")
    source_dir = os.path.join(PROJECT, "src")
    assert os.path.isfile(manifest), f"Cargo manifest missing at {manifest}"
    assert os.path.isdir(source_dir), f"Rust source directory missing at {source_dir}"
    assert any(name.endswith(".rs") for _, _, files in os.walk(source_dir) for name in files), \
        "No Rust source files found in the Cargo project"

    if os.path.lexists(BINARY):
        os.unlink(BINARY)
    result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"cargo build --release failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(BINARY), f"Rust binary not produced at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Rust binary at {BINARY} is not executable"


def test_audio_filter_corpus():
    """Verify the Rust binary correctly classifies the clean and evil corpora."""
    assert os.path.isfile(BINARY), f"Rust binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Rust binary at {BINARY} is not executable"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".wav")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".wav")]
    assert len(clean_files) > 0, "No clean files found to test."
    assert len(evil_files) > 0, "No evil files found to test."

    clean_failed = []
    for path in clean_files:
        if subprocess.run([BINARY, path], capture_output=True).returncode != 0:
            clean_failed.append(os.path.basename(path))

    evil_failed = []
    for path in evil_files:
        if subprocess.run([BINARY, path], capture_output=True).returncode != 1:
            evil_failed.append(os.path.basename(path))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected instead of accepted): {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed (accepted instead of rejected): {', '.join(evil_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def write_wav(path, sample_rate):
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(b"\x00\x00" * 37)


def test_audio_filter_on_unseen_random_paths_and_metadata():
    """Exercise unseen WAV headers so corpus filenames and paths cannot be used as labels."""
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    safe_rates = [48000, 47999, secrets.randbelow(40000) + 8000]
    evil_rates = [48001, 96000, secrets.randbelow(100000) + 100001]
    cases = [(rate, 0) for rate in safe_rates] + [(rate, 1) for rate in evil_rates]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="wav-verification-") as root:
        generated = []
        for rate, expected in cases:
            directory = os.path.join(root, secrets.token_hex(8))
            os.makedirs(directory)
            path = os.path.join(directory, secrets.token_hex(12) + ".wav")
            write_wav(path, rate)
            generated.append((path, rate, expected))

        for path, rate, expected in generated:
            result = subprocess.run([BINARY, os.path.abspath(path)], capture_output=True, timeout=10)
            assert result.returncode == expected, \
                f"sample rate {rate} Hz returned {result.returncode}, expected {expected}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
