#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import tempfile
import time

import pytest

REPORT_PATH = "/home/user/security_report.json"
MAIN_RS_PATH = "/home/user/rogue_service/src/main.rs"
CARGO_TOML_PATH = "/home/user/rogue_service/Cargo.toml"
PROJECT_DIR = "/home/user/rogue_service"
BINARY_PATH = "/home/user/rogue_service/target/debug/rogue_service"


def test_security_report_exists_and_valid():
    assert os.path.isfile(REPORT_PATH), f"Security report not found at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    assert "discovered_port" in report, "Missing 'discovered_port' in report."
    assert report["discovered_port"] == 8123, (
        f"Incorrect discovered_port. Expected 8123, got {report['discovered_port']}."
    )

    assert "vulnerabilities" in report, "Missing 'vulnerabilities' in report."
    vulns = report["vulnerabilities"]
    assert isinstance(vulns, list), "'vulnerabilities' must be a list."
    assert "CWE-77" in vulns, "Missing CWE-77 (Command Injection) in vulnerabilities."
    assert "CWE-79" in vulns, "Missing CWE-79 (XSS) in vulnerabilities."

    assert "csp_header_added" in report, "Missing 'csp_header_added' in report."
    csp_val = report["csp_header_added"].strip()
    assert csp_val in ["default-src 'self'", "Content-Security-Policy: default-src 'self'"], (
        f"Incorrect csp_header_added value. Got: {csp_val}"
    )


def test_main_rs_fixes_applied():
    assert os.path.isfile(MAIN_RS_PATH), f"Source file not found at {MAIN_RS_PATH}"

    with open(MAIN_RS_PATH, "r") as f:
        content = f.read()

    # Retain the original source assertions.
    assert "Content-Security-Policy: default-src 'self'" in content, (
        "The required Content-Security-Policy header was not found in the HTTP response."
    )
    assert 'Command::new("sh")' not in content or '".arg("-c")' not in content.replace(" ", "").replace("\n", ""), (
        "The Command Injection vulnerability using `sh -c` is still present."
    )

    # Reject direct use of common shell interpreters or a shell command flag in active source.
    without_comments = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    without_comments = re.sub(r"//[^\n]*", "", without_comments)
    compact = re.sub(r"\s+", "", without_comments)
    assert not re.search(
        r'Command::new\((?:r#)?["\'](?:/[^"\']*/)?(?:sh|bash|dash|zsh|ksh)(?:"#|["\'])\)',
        compact,
    ), "A shell interpreter is still being launched by Command::new."
    assert not re.search(r'\.arg\((?:r#)?["\']-c(?:"#|["\'])\)', compact), (
        "The command is still being passed through a shell-style -c argument."
    )
    assert "Command::new(" in without_comments, "The service no longer invokes the intended command."
    assert ".arg(" in without_comments or ".args(" in without_comments, (
        "The command must receive its input through a separate argument."
    )


def test_cargo_check_succeeds():
    assert os.path.isfile(CARGO_TOML_PATH), f"Cargo.toml not found at {CARGO_TOML_PATH}"

    result = subprocess.run(
        ["cargo", "check", "--manifest-path", CARGO_TOML_PATH],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"cargo check failed with exit code {result.returncode}.\nStderr: {result.stderr}"
    )


def request_service():
    last_error = None
    for _ in range(50):
        try:
            with socket.create_connection(("127.0.0.1", 8123), timeout=0.25) as sock:
                sock.settimeout(2)
                sock.sendall(
                    b"GET /?cmd=test%3Btouch%20%2Ftmp%2Finjected HTTP/1.1\r\n"
                    b"Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
                )
                chunks = []
                while True:
                    data = sock.recv(4096)
                    if not data:
                        break
                    chunks.append(data)
                return b"".join(chunks)
        except (ConnectionRefusedError, OSError) as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Service did not listen on port 8123: {last_error}")


def test_running_service_emits_csp_and_invokes_command_with_one_argument():
    build = subprocess.run(
        ["cargo", "build", "--manifest-path", CARGO_TOML_PATH],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"cargo build failed:\n{build.stderr}"
    assert os.path.isfile(BINARY_PATH), "cargo build did not produce the service binary."

    # Temporarily instrument echo, including absolute /bin/echo and /usr/bin/echo uses.
    echo_path = os.path.realpath("/bin/echo")
    assert os.path.isfile(echo_path), "System echo executable is unavailable."
    temp_dir = tempfile.mkdtemp(prefix="verify-command-")
    backup_path = os.path.join(temp_dir, "echo.backup")
    log_path = os.path.join(temp_dir, "argv.jsonl")
    shutil.copy2(echo_path, backup_path)

    logger = f'''#!/usr/bin/python3
import json, os, sys
with open({log_path!r}, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
'''

    proc = None
    try:
        with open(echo_path, "w") as f:
            f.write(logger)
        os.chmod(echo_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        proc = subprocess.Popen(
            [BINARY_PATH],
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=os.environ.copy(),
        )
        response = request_service()

        assert b"\r\n\r\n" in response, "Service did not return a valid HTTP header block."
        header_block = response.split(b"\r\n\r\n", 1)[0]
        header_lines = header_block.split(b"\r\n")
        assert b"Content-Security-Policy: default-src 'self'" in header_lines, (
            "The running service did not emit the exact CSP as an HTTP response header."
        )

        deadline = time.time() + 2
        while time.time() < deadline and not os.path.exists(log_path):
            time.sleep(0.05)
        assert os.path.isfile(log_path), "The running service did not execute the intended echo command."

        with open(log_path, "r") as f:
            invocations = [json.loads(line) for line in f if line.strip()]
        assert invocations, "No command invocation was recorded while handling the request."
        assert all(len(argv) == 1 for argv in invocations), (
            "Command input was not passed as exactly one separate process argument."
        )
        assert all(argv[0] == "user_input" for argv in invocations), (
            "The service did not preserve the original command argument semantics."
        )
        assert not os.path.exists("/tmp/injected"), "The request caused shell command injection."
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        shutil.copy2(backup_path, echo_path)
        shutil.rmtree(temp_dir, ignore_errors=True)
        try:
            os.remove("/tmp/injected")
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
