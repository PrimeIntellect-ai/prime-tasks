#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import threading
import time
import uuid

import pytest

APP = "/home/user/app_fw"
EXPECT_SCRIPT = "/home/user/test_fw.exp"
START_SCRIPT = "/home/user/start.sh"
GROUPS = "/home/user/groups.txt"
SUCCESS_LOG = "/home/user/success.log"


def kill_firewall():
    subprocess.run(
        ["pkill", "-f", r"^/home/user/app_fw( |$)"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.1)


def query_daemon(username, timeout=6):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 7777), timeout=1) as sock:
                sock.settimeout(2)
                prompt = b""
                while not prompt.endswith(b"Username: "):
                    chunk = sock.recv(1024)
                    if not chunk:
                        break
                    prompt += chunk
                assert prompt == b"Username: ", f"Unexpected daemon prompt: {prompt!r}"
                sock.sendall(username.encode() + b"\n")
                response = b""
                while b"\n" not in response:
                    chunk = sock.recv(1024)
                    if not chunk:
                        break
                    response += chunk
                return response.decode(errors="replace").strip()
        except (ConnectionRefusedError, OSError) as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Daemon did not become reachable: {last_error}")


def test_app_fw_compiled():
    """Verify that the C daemon has been compiled and is executable."""
    assert os.path.isfile(APP), f"The compiled executable {APP} is missing. Did you compile app_fw.c?"
    assert os.access(APP, os.X_OK), f"The file {APP} is not executable."
    with open(APP, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{APP} is not a compiled ELF executable."


def test_check_group_through_running_daemon():
    """Run the submitted daemon and verify check_group reads the groups file."""
    with open(GROUPS, "rb") as f:
        original_groups = f.read()

    allowed = "allowed_" + uuid.uuid4().hex
    denied = "denied_" + uuid.uuid4().hex
    near_group = "near_" + uuid.uuid4().hex
    proc = None
    try:
        with open(GROUPS, "w") as f:
            f.write(f"{denied}:users\n")
            f.write(f"{allowed}:migrators\n")
            f.write(f"{near_group}:migrators-extra\n")

        kill_firewall()
        proc = subprocess.Popen(APP, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

        allowed_response = query_daemon(allowed)
        denied_response = query_daemon(denied)
        near_response = query_daemon(near_group)

        assert allowed_response.startswith("TOKEN: "), (
            f"A randomized user in migrators was rejected: {allowed_response!r}"
        )
        assert denied_response == "Access Denied", (
            f"A randomized non-migrator was accepted: {denied_response!r}"
        )
        assert near_response == "Access Denied", (
            f"A non-exact group name was accepted: {near_response!r}"
        )
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        kill_firewall()
        with open(GROUPS, "wb") as f:
            f.write(original_groups)


def test_test_fw_exp_exists():
    """Verify that the Expect script was created."""
    assert os.path.isfile(EXPECT_SCRIPT), f"The expect script {EXPECT_SCRIPT} is missing."


def test_expect_script_captures_runtime_token():
    """Execute the Expect script against a server with an unpredictable token."""
    kill_firewall()
    token_line = "TOKEN: " + uuid.uuid4().hex
    received = []
    server_error = []

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 7777))
    server.listen(1)
    server.settimeout(8)

    def serve():
        try:
            conn, _ = server.accept()
            with conn:
                conn.settimeout(3)
                conn.sendall(b"Username: ")
                data = b""
                while b"\n" not in data:
                    chunk = conn.recv(1024)
                    if not chunk:
                        break
                    data += chunk
                received.append(data.decode(errors="replace").strip())
                conn.sendall((token_line + "\n").encode())
        except Exception as exc:
            server_error.append(repr(exc))
        finally:
            server.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    try:
        if os.path.exists(SUCCESS_LOG):
            os.remove(SUCCESS_LOG)
        result = subprocess.run(
            ["expect", EXPECT_SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=10,
        )
        thread.join(timeout=9)
        assert not thread.is_alive(), "The Expect script never connected to the test server."
        assert not server_error, f"Test server failed: {server_error}"
        assert result.returncode == 0, f"Expect script failed:\n{result.stdout}"
        assert received == ["alice"], f"Expect script sent the wrong username: {received!r}"
        assert os.path.isfile(SUCCESS_LOG), "Expect script did not create success.log."
        with open(SUCCESS_LOG) as f:
            actual = f.read().strip()
        assert actual == token_line, (
            f"Expect script did not write the exact runtime token line; found {actual!r}"
        )
    finally:
        server.close()
        thread.join(timeout=1)


def test_start_sh_fixed():
    """Verify start.sh contains a real loop and programmatic port probe."""
    assert os.path.isfile(START_SCRIPT), f"The file {START_SCRIPT} is missing."
    with open(START_SCRIPT) as f:
        content = f.read()

    # Preserve the original assertions.
    has_loop = "while" in content or "until" in content
    has_port = "7777" in content
    assert has_loop, "start.sh does not appear to contain a loop (while/until) to wait for the port."
    assert has_port, "start.sh does not appear to check for port 7777."

    # Ignore comments so the example shipped by setup cannot satisfy the check.
    code = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    assert re.search(r"\b(?:while|until)\b", code), (
        "start.sh has no executable while/until wait loop."
    )
    port_probes = (
        r"\bnc\b[^\n]*(?:-z[^\n]*7777|7777[^\n]*-z)",
        r"/dev/tcp/[^\s;]+/7777",
        r"\b(?:ss|netstat|lsof)\b[^\n]*7777",
    )
    assert any(re.search(pattern, code) for pattern in port_probes), (
        "start.sh does not programmatically probe whether port 7777 is listening."
    )
    assert re.search(r"\bexpect\b[^\n]*/home/user/test_fw\.exp\b", code), (
        "start.sh does not execute the required Expect script."
    )


def test_startup_and_success_log():
    """Run start.sh from a clean state and verify it produces the real token."""
    kill_firewall()
    if os.path.exists(SUCCESS_LOG):
        os.remove(SUCCESS_LOG)

    try:
        result = subprocess.run(
            [START_SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"start.sh failed:\n{result.stdout}"
        assert os.path.isfile(SUCCESS_LOG), (
            f"The file {SUCCESS_LOG} is missing. The script may have failed to execute or write the output."
        )
        with open(SUCCESS_LOG) as f:
            content = f.read().strip()

        expected_token = "TOKEN: MIGRATION_AUTH_994827"
        assert expected_token in content, (
            f"success.log does not contain the expected token {expected_token!r}. Found: {content}"
        )
        assert content == expected_token, "success.log must contain exactly the token line."
    finally:
        kill_firewall()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
