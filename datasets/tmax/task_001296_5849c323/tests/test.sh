#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import stat
import subprocess
import time
import pytest


def test_task1_vuln_files_log():
    log_path = "/home/user/vuln_files.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_files = {
        "/home/user/auditing_workspace/www/script.js",
        "/home/user/auditing_workspace/www/style.css"
    }

    assert set(lines) == expected_files, f"Log file must contain exactly the world-writable files. Found: {lines}"


def test_task1_permissions():
    www_dir = "/home/user/auditing_workspace/www"
    assert os.path.isdir(www_dir), f"Directory {www_dir} does not exist."

    dir_stat = os.stat(www_dir)
    dir_perm = stat.S_IMODE(dir_stat.st_mode)
    assert dir_perm == 0o755, f"Directory {www_dir} has permissions {oct(dir_perm)}, expected 0o755."

    for root, dirs, files in os.walk(www_dir):
        for d in dirs:
            d_path = os.path.join(root, d)
            d_perm = stat.S_IMODE(os.stat(d_path).st_mode)
            assert d_perm == 0o755, f"Directory {d_path} has permissions {oct(d_perm)}, expected 0o755."
        for f in files:
            f_path = os.path.join(root, f)
            f_perm = stat.S_IMODE(os.stat(f_path).st_mode)
            assert f_perm == 0o644, f"File {f_path} has permissions {oct(f_perm)}, expected 0o644."


def test_task2_csp_header():
    main_rs_path = "/home/user/auditing_workspace/web_server/src/main.rs"
    assert os.path.isfile(main_rs_path), f"File {main_rs_path} does not exist."

    with open(main_rs_path, "r") as f:
        content = f.read()

    expected_csp = "Content-Security-Policy: default-src 'self'; script-src 'self' https://trusted.cdn.com"
    assert expected_csp in content, "The expected CSP header was not found in main.rs."
    assert re.search(r"Content-Security-Policy:.*\\r\\n", content) is not None, "CSP header does not appear to be properly inserted in the HTTP header block with \\r\\n."


def test_task2_cargo_build():
    web_server_dir = "/home/user/auditing_workspace/web_server"
    assert os.path.isdir(web_server_dir), f"Directory {web_server_dir} does not exist."

    result = subprocess.run(
        ["cargo", "build"],
        cwd=web_server_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    assert result.returncode == 0, f"cargo build failed:\n{result.stderr.decode('utf-8', errors='replace')}"


def test_task2_served_response_contains_csp_header():
    web_server_dir = "/home/user/auditing_workspace/web_server"
    expected_header = b"Content-Security-Policy: default-src 'self'; script-src 'self' https://trusted.cdn.com"

    proc = subprocess.Popen(
        ["cargo", "run", "--quiet"],
        cwd=web_server_dir,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE
    )
    try:
        sock = None
        last_error = None
        for _ in range(50):
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode("utf-8", errors="replace")
                pytest.fail(f"Web server exited before accepting a connection:\n{stderr}")
            try:
                sock = socket.create_connection(("127.0.0.1", 8080), timeout=0.5)
                break
            except OSError as exc:
                last_error = exc
                time.sleep(0.1)

        assert sock is not None, f"Could not connect to the web server: {last_error}"
        with sock:
            sock.settimeout(2)
            sock.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
            chunks = []
            while True:
                try:
                    chunk = sock.recv(4096)
                except socket.timeout:
                    break
                if not chunk:
                    break
                chunks.append(chunk)

        response = b"".join(chunks)
        assert b"\r\n\r\n" in response, f"Server did not return a valid HTTP header block: {response!r}"
        header_block = response.split(b"\r\n\r\n", 1)[0]
        header_lines = header_block.split(b"\r\n")
        assert expected_header in header_lines, f"Served HTTP response is missing the exact CSP header. Headers: {header_lines!r}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)


def test_task3_ssh_hardening():
    sshd_config_path = "/home/user/auditing_workspace/sshd_config_custom"
    assert os.path.isfile(sshd_config_path), f"File {sshd_config_path} does not exist."

    with open(sshd_config_path, "r") as f:
        lines = f.readlines()

    permit_root_login_no = False
    password_auth_no = False

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        if re.match(r"^PermitRootLogin\s+yes", line, re.IGNORECASE):
            pytest.fail("PermitRootLogin is still set to 'yes' (uncommented).")
        if re.match(r"^PasswordAuthentication\s+yes", line, re.IGNORECASE):
            pytest.fail("PasswordAuthentication is still set to 'yes' (uncommented).")

        if re.match(r"^PermitRootLogin\s+no", line, re.IGNORECASE):
            permit_root_login_no = True
        if re.match(r"^PasswordAuthentication\s+no", line, re.IGNORECASE):
            password_auth_no = True

    assert permit_root_login_no, "PermitRootLogin is not explicitly set to 'no'."
    assert password_auth_no, "PasswordAuthentication is not explicitly set to 'no'."

    expected = (
        "Port 2222\n"
        "PermitRootLogin no\n"
        "PasswordAuthentication no\n"
        "X11Forwarding no\n"
    )
    with open(sshd_config_path, "r") as f:
        actual = f.read()
    assert actual == expected, "SSH directives must have the exact value 'no', and all other configuration content must remain intact."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
