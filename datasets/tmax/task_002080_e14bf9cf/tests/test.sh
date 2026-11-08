#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import signal
import socket
import string
import subprocess
import tempfile
import time

WORKSPACE_DIR = "/home/user/workspace"
PORT = 9090


def test_investigation_txt():
    report_path = os.path.join(WORKSPACE_DIR, "investigation.txt")
    assert os.path.exists(report_path), f"Report file missing: {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 3, "investigation.txt must have at least 3 lines."
    assert "LD_LIBRARY_PATH" in lines[0], "Line 1 does not contain LD_LIBRARY_PATH"
    assert "/home/user/workspace/hidden_init.cfg" in lines[1], "Line 2 does not contain the correct absolute path"
    assert "std::domain_error" in lines[2], "Line 3 does not contain the correct exception type"


def test_hidden_init_cfg():
    cfg_path = os.path.join(WORKSPACE_DIR, "hidden_init.cfg")
    assert os.path.exists(cfg_path), f"Configuration file missing: {cfg_path}"

    with open(cfg_path, "r") as f:
        content = f.read().strip()

    assert content == "ENABLE", f"Expected 'ENABLE' in {cfg_path}, found '{content}'"


def matching_brace(text, opening):
    depth = 0
    state = "code"
    i = opening
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if c == '"':
                state = "string"
            elif c == "'":
                state = "char"
            elif c == "/" and n == "/":
                state = "line_comment"
                i += 1
            elif c == "/" and n == "*":
                state = "block_comment"
                i += 1
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return i
        elif state == "string":
            if c == "\\":
                i += 1
            elif c == '"':
                state = "code"
        elif state == "char":
            if c == "\\":
                i += 1
            elif c == "'":
                state = "code"
        elif state == "line_comment":
            if c == "\n":
                state = "code"
        elif state == "block_comment" and c == "*" and n == "/":
            state = "code"
            i += 1
        i += 1
    raise AssertionError("Unbalanced braces in server.cpp")


def test_server_cpp_patched():
    cpp_path = os.path.join(WORKSPACE_DIR, "server.cpp")
    assert os.path.exists(cpp_path), f"Source file missing: {cpp_path}"

    with open(cpp_path, "r") as f:
        content = f.read()

    assert "[SECURITY] Caught malicious abort" in content, "server.cpp does not contain the required security print statement."
    assert "catch" in content, "server.cpp does not appear to catch the exception."

    process_match = re.search(r"\bvoid\s+process_client\s*\([^)]*\)\s*\{", content)
    assert process_match, "process_client function is missing."
    process_open = content.find("{", process_match.start())
    process_close = matching_brace(content, process_open)
    process_body = content[process_open + 1:process_close]

    thread_match = re.search(r"std::thread\s+\w+\s*\(\s*\[[^]]*\]\s*\([^)]*\)\s*\{", process_body)
    assert thread_match, "The detached std::thread worker architecture is missing."
    lambda_open = process_body.find("{", thread_match.start())
    lambda_close = matching_brace(process_body, lambda_open)
    lambda_body = process_body[lambda_open + 1:lambda_close]

    assert re.search(r"throw\s+std::domain_error\s*\(", lambda_body), "The original std::domain_error path is missing from the worker."
    try_match = re.search(r"\btry\s*\{", lambda_body)
    assert try_match, "The worker thread does not contain a try block."
    try_open = lambda_body.find("{", try_match.start())
    try_close = matching_brace(lambda_body, try_open)
    try_body = lambda_body[try_open + 1:try_close]
    assert re.search(r"throw\s+std::domain_error\s*\(", try_body), "The throwing operation is not protected by the worker's try block."

    catch_match = re.search(r"\bcatch\s*\([^)]*\)\s*\{", lambda_body[try_close + 1:])
    assert catch_match, "The exception is not caught inside the detached worker thread."
    catch_start = try_close + 1 + catch_match.start()
    catch_open = lambda_body.find("{", catch_start)
    catch_close = matching_brace(lambda_body, catch_open)
    catch_body = lambda_body[catch_open + 1:catch_close]
    assert "[SECURITY] Caught malicious abort" in catch_body, "The required message is not printed from the worker's catch block."
    assert re.search(r"\.detach\s*\(\s*\)", process_body[lambda_close + 1:]), "The worker is no longer detached."


def listener_inodes():
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and int(fields[1].split(":")[-1], 16) == PORT and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def pid_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        for name in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, name))
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match:
                result.add(match.group(1))
    except FileNotFoundError:
        pass
    return result


def kill_existing_listeners():
    inodes = listener_inodes()
    if not inodes:
        return
    for entry in os.listdir("/proc"):
        if entry.isdigit() and int(entry) != os.getpid() and pid_socket_inodes(int(entry)) & inodes:
            try:
                os.kill(int(entry), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
    time.sleep(0.2)


def send_payload(payload, expect_reply, retries=1):
    last_error = None
    for _ in range(retries):
        try:
            with socket.create_connection(("127.0.0.1", PORT), timeout=1.0) as sock:
                sock.settimeout(1.5)
                sock.sendall(payload.encode())
                if expect_reply:
                    return sock.recv(1024)
                try:
                    sock.recv(1024)
                except (socket.timeout, ConnectionResetError):
                    pass
                return b""
        except OSError as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Could not exchange payload with server: {last_error}")


def test_server_and_client_execution():
    kill_existing_listeners()

    make_result = subprocess.run(["make", "-B"], cwd=WORKSPACE_DIR, capture_output=True, text=True, timeout=30)
    assert make_result.returncode == 0, f"Failed to compile server:\n{make_result.stderr}"

    server_exe = os.path.join(WORKSPACE_DIR, "server")
    assert os.path.exists(server_exe), "Server binary not found after make."
    with open(server_exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The built server is not a native compiled executable."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = os.path.join(WORKSPACE_DIR, "lib") + ":" + env.get("LD_LIBRARY_PATH", "")

    log_file = tempfile.NamedTemporaryFile(mode="w+", delete=False)
    server_process = subprocess.Popen(
        [server_exe], cwd=WORKSPACE_DIR, env=env,
        stdout=log_file, stderr=subprocess.STDOUT, text=True
    )

    try:
        nonce = "".join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=24))
        reply = send_payload("PING_" + nonce, True, retries=30)
        assert reply == b"OK\n", f"Server returned an incorrect normal response: {reply!r}"
        assert server_process.poll() is None, "Server crashed or exited immediately upon startup."

        listening = listener_inodes()
        assert listening & pid_socket_inodes(server_process.pid), "The launched server process is not the process listening on port 9090."

        malicious = "prefix_" + nonce + "_ABORT_SEQ_suffix"
        send_payload(malicious, False)
        time.sleep(0.4)
        assert server_process.poll() is None, "Server crashed while handling the malicious payload."

        reply = send_payload("FINAL_" + nonce, True)
        assert reply == b"OK\n", "Server did not process a normal payload after the malicious payload."

        log_file.flush()
        with open(log_file.name) as f:
            output = f.read()
        assert "[SECURITY] Caught malicious abort" in output, "Server did not print the required security message when catching the exception."

        client_result = subprocess.run(
            ["python3", "client.py"], cwd=WORKSPACE_DIR,
            capture_output=True, text=True, timeout=15
        )
        assert client_result.returncode == 0, f"Client script failed:\n{client_result.stderr}"
        assert "All payloads processed successfully." in client_result.stdout, "Client did not complete all payloads successfully."
        assert server_process.poll() is None, "Server crashed during client execution."

        reply = send_payload("POST_CLIENT_" + nonce, True)
        assert reply == b"OK\n", "Server was not functional after the full client sequence."
    finally:
        if server_process.poll() is None:
            server_process.terminate()
            try:
                server_process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                server_process.kill()
                server_process.wait(timeout=2)
        log_file.close()
        try:
            os.unlink(log_file.name)
        except FileNotFoundError:
            pass
        kill_existing_listeners()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
