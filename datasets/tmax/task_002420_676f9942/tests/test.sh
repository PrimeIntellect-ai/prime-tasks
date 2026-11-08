#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

PROJECT = "/home/user/health_monitor"
BINARY = PROJECT + "/target/release/monitor"
LOG = "/home/user/logs/monitor.log"
WRAPPER = "/home/user/run_monitor.sh"


def run_as_user(command, cwd=None, timeout=30):
    cmd = [
        "runuser", "-u", "user", "--",
        "env", "-i",
        "HOME=/home/user", "USER=user", "LOGNAME=user",
        "PATH=/usr/bin:/bin",
    ] + command
    return subprocess.run(
        cmd, cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout
    )


def extracted_config():
    result = subprocess.run(
        ["tesseract", "/app/target_config.png", "stdout", "--psm", "6"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=30, check=True
    )
    text = result.stdout.upper()
    port_match = re.search(r"TARGET[\s_:.-]*PORT\s*:\s*(\d+)", text)
    token_match = re.search(r"SECRET[\s_:.-]*TOKEN\s*:\s*([A-Z0-9-]+)", text)
    assert port_match, f"Could not extract TARGET_PORT from dashboard image. OCR output: {text!r}"
    assert token_match, f"Could not extract SECRET_TOKEN from dashboard image. OCR output: {text!r}"
    return port_match.group(1), token_match.group(1)


def test_binary_size():
    binary_path = "/home/user/health_monitor/target/release/monitor"
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}"

    size = os.path.getsize(binary_path)
    threshold = 400000
    assert size <= threshold, f"Binary size is {size} bytes, which exceeds the threshold of {threshold} bytes."


def test_configuration_and_project_changes():
    port, token = extracted_config()
    assert port == "8899" and token == "EDGE-MIGRATE-2024", "The supplied dashboard image was altered or misread"

    main_path = PROJECT + "/src/main.rs"
    cargo_path = PROJECT + "/Cargo.toml"
    assert os.path.isfile(main_path), f"Rust source not found at {main_path}"
    assert os.path.isfile(cargo_path), f"Cargo manifest not found at {cargo_path}"

    with open(main_path, encoding="utf-8") as f:
        source = f.read()
    assert 'let port = "0000"' not in source and 'let token = "UNKNOWN"' not in source, \
        "The Rust source still contains the original placeholder configuration"

    with open(cargo_path, encoding="utf-8") as f:
        cargo = f.read()
    original_cargo = '''[package]
name = "monitor"
version = "0.1.0"
edition = "2021"

[dependencies]
'''
    assert cargo != original_cargo, "Cargo.toml was not modified for size optimization"
    profile = re.search(r"(?ms)^\s*\[profile\.release\]\s*(.*?)(?=^\s*\[|\Z)", cargo)
    assert profile, "Cargo.toml does not contain a release optimization profile"
    assert re.search(r"(?m)^\s*(opt-level|lto|strip|panic|codegen-units)\s*=", profile.group(1)), \
        "The release profile contains no recognized size optimization setting"


def test_clean_rebuild_and_binary_execution():
    clean = run_as_user(["/usr/bin/cargo", "clean"], cwd=PROJECT, timeout=60)
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}\n{clean.stderr}"

    build = run_as_user(["/usr/bin/cargo", "build", "--release"], cwd=PROJECT, timeout=180)
    assert build.returncode == 0, f"Clean release build failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(BINARY), f"Clean Cargo build did not produce {BINARY}"
    assert os.path.getsize(BINARY) <= 400000, \
        f"Rebuilt binary is {os.path.getsize(BINARY)} bytes, exceeding 400000 bytes"

    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The monitor artifact is not a compiled ELF binary"

    port, token = extracted_config()
    expected = f"Connecting to 127.0.0.1:{port} with token {token}"
    executed = run_as_user([BINARY], timeout=10)
    assert executed.returncode == 0, f"Monitor execution failed:\n{executed.stdout}\n{executed.stderr}"
    assert expected in executed.stdout, f"Monitor produced incorrect output: {executed.stdout!r}"


def test_log_output():
    assert os.path.isfile(WRAPPER), f"Wrapper script not found at {WRAPPER}"
    assert os.access(WRAPPER, os.X_OK), f"Wrapper script is not executable: {WRAPPER}"

    if os.path.lexists(LOG):
        os.unlink(LOG)

    result = run_as_user([WRAPPER], timeout=15)
    assert result.returncode == 0, f"run_monitor.sh failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(LOG), f"Log file not found at {LOG}. Did you fix run_monitor.sh and run it?"

    with open(LOG, "r") as f:
        content = f.read()

    expected_text = "Connecting to 127.0.0.1:8899 with token EDGE-MIGRATE-2024"
    assert expected_text in content, f"Log file does not contain the expected output. Found: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
