#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import secrets
import subprocess
import time
import pytest

PROFILE_PATH = "/home/user/.bash_profile"
CONFIG_PATH = "/home/user/nginx/nginx.conf"
CACHE_DIR = "/home/user/backend/cache"
INDEX_PATH = os.path.join(CACHE_DIR, "index.html")
EXPECTED_RESPONSE = b"Hello from the backend!\n"


def get_backend_port():
    with open(PROFILE_PATH, "r") as f:
        content = f.read()
    match = re.search(r'export\s+BACKEND_PORT=(\d+)', content)
    assert match is not None, "BACKEND_PORT environment variable is not exported in .bash_profile."
    return int(match.group(1))


def curl(url):
    result = subprocess.run(
        ["curl", "-fsS", "--max-time", "3", url],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, (
        f"curl request to {url} failed with status {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    return result.stdout


def test_success_log_content():
    log_path = "/home/user/success.log"
    assert os.path.isfile(log_path), f"Expected file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read()

    assert "Hello from the backend!" in content, (
        f"File {log_path} does not contain the expected success message. "
        f"Found: {content.strip()}"
    )


def test_backend_cache_directory_exists():
    cache_dir = "/home/user/backend/cache"
    assert os.path.isdir(cache_dir), f"The backend cache directory {cache_dir} was not created."


def test_bash_profile_contains_backend_port():
    profile_path = "/home/user/.bash_profile"
    assert os.path.isfile(profile_path), f"File {profile_path} is missing."

    with open(profile_path, "r") as f:
        content = f.read()

    # Look for export BACKEND_PORT=<port>
    match = re.search(r'export\s+BACKEND_PORT=(\d+)', content)
    assert match is not None, "BACKEND_PORT environment variable is not exported in .bash_profile."

    port = int(match.group(1))
    assert port > 1024, f"BACKEND_PORT {port} should be a high, unused port."


def test_nginx_config_updated_with_correct_port():
    profile_path = "/home/user/.bash_profile"
    with open(profile_path, "r") as f:
        content = f.read()
    match = re.search(r'export\s+BACKEND_PORT=(\d+)', content)
    if not match:
        pytest.fail("Cannot verify nginx config because BACKEND_PORT is not in .bash_profile")

    backend_port = match.group(1)

    config_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx config {config_path} is missing."

    with open(config_path, "r") as f:
        config_content = f.read()

    expected_proxy_pass = f"proxy_pass http://127.0.0.1:{backend_port};"
    assert expected_proxy_pass in config_content or f"proxy_pass http://localhost:{backend_port};" in config_content, (
        f"Nginx config does not contain the correct proxy_pass directive for port {backend_port}."
    )


def test_backend_process_running():
    profile_path = "/home/user/.bash_profile"
    with open(profile_path, "r") as f:
        content = f.read()
    match = re.search(r'export\s+BACKEND_PORT=(\d+)', content)
    if not match:
        pytest.fail("Cannot verify backend process because BACKEND_PORT is not in .bash_profile")

    backend_port = match.group(1)

    try:
        output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
        assert backend_port in output and "python3" in output, (
            f"Backend process (python3 -m http.server {backend_port}) does not appear to be running."
        )
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run ps aux to check for backend process.")


def test_backend_pid_is_real_http_server():
    port = get_backend_port()
    pid_path = "/home/user/backend/backend.pid"
    assert os.path.isfile(pid_path), f"Backend PID file {pid_path} is missing."

    with open(pid_path, "r") as f:
        pid_text = f.read().strip()
    assert pid_text.isdigit(), f"Backend PID file contains an invalid PID: {pid_text!r}"

    pid = int(pid_text)
    proc_dir = f"/proc/{pid}"
    assert os.path.isdir(proc_dir), f"Backend process {pid} is not running."

    with open(f"{proc_dir}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode("utf-8", errors="replace")
    assert re.search(rf"python3(?:\s|\S)*-m\s+http\.server\s+{port}(?:\s|$)", cmdline), (
        f"PID {pid} is not the expected Python HTTP server on port {port}: {cmdline!r}"
    )
    assert os.path.realpath(f"{proc_dir}/cwd") == CACHE_DIR, (
        f"Backend process is not serving the required cache directory {CACHE_DIR}."
    )


def test_nginx_configuration_is_valid_and_running():
    result = subprocess.run(
        ["nginx", "-t", "-c", CONFIG_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, (
        "The updated Nginx configuration is invalid: "
        + result.stderr.decode("utf-8", errors="replace")
    )

    found_master = False
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                command = f.read().replace(b"\0", b" ")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if b"nginx: master process" in command and CONFIG_PATH.encode() in command:
            found_master = True
            break
    assert found_master, f"No running Nginx master process is using {CONFIG_PATH}."


def test_live_backend_and_nginx_proxy_with_dynamic_content():
    port = get_backend_port()
    assert os.path.isfile(INDEX_PATH), f"Backend content file {INDEX_PATH} is missing."

    with open(INDEX_PATH, "rb") as f:
        original_content = f.read()

    challenge = ("verifier-" + secrets.token_hex(24) + "\n").encode("ascii")
    try:
        with open(INDEX_PATH, "wb") as f:
            f.write(challenge)

        direct = curl(f"http://127.0.0.1:{port}/?verify={secrets.token_hex(8)}")
        assert direct == challenge, (
            "The configured backend port is not serving the backend cache directory."
        )

        frontend = curl(f"http://127.0.0.1:8080/?verify={secrets.token_hex(8)}")
        assert frontend == challenge, (
            "Port 8080 did not return the dynamic content served by the configured backend; "
            "Nginx is not proxying to the backend correctly."
        )
    finally:
        with open(INDEX_PATH, "wb") as f:
            f.write(original_content)

    time.sleep(0.05)
    live_response = curl(f"http://127.0.0.1:8080/?final={secrets.token_hex(8)}")
    assert live_response == EXPECTED_RESPONSE, (
        f"The live stack returned {live_response!r}, expected {EXPECTED_RESPONSE!r}."
    )

    with open("/home/user/success.log", "rb") as f:
        saved_response = f.read()
    assert saved_response == live_response, (
        "/home/user/success.log is not exactly the output currently returned by the full stack."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
