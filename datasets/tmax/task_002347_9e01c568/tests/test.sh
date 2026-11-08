#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import secrets
import socket
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest


def test_limits_registered():
    path = "/home/user/.limits_registered"
    assert os.path.isfile(path), f"File {path} not found. Did the Expect script run successfully?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"Expected 'SUCCESS' in {path}, got '{content}'"

    expect_path = "/home/user/setup_limits.exp"
    assert os.path.isfile(expect_path), f"Expect script not found at {expect_path}"
    assert os.access(expect_path, os.X_OK), f"Expect script at {expect_path} is not executable"


def run_sanitiser(path):
    return subprocess.run(
        ["/home/user/sanitiser", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def test_sanitiser_corpus():
    sanitiser_path = "/home/user/sanitiser"
    assert os.path.isfile(sanitiser_path), f"Sanitiser executable not found at {sanitiser_path}"
    assert os.access(sanitiser_path, os.X_OK), f"Sanitiser at {sanitiser_path} is not executable"
    assert os.path.isfile("/home/user/sanitiser.c"), "Sanitiser C source not found"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_failed = []
    for root, _, files in os.walk(clean_dir):
        for file in files:
            filepath = os.path.join(root, file)
            res = run_sanitiser(filepath)
            if res.returncode != 0:
                clean_failed.append(file)

    evil_failed = []
    for root, _, files in os.walk(evil_dir):
        for file in files:
            filepath = os.path.join(root, file)
            res = run_sanitiser(filepath)
            if res.returncode == 0:
                evil_failed.append(file)

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} clean files rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} evil files bypassed: {', '.join(evil_failed)}")
    assert not errors, " | ".join(errors)


def test_sanitiser_generated_inputs():
    token = secrets.token_hex(8)
    host = f"node-{token}-A9"
    timestamp = "2026-04-17T13:14:15Z"

    valid_documents = [
        f"{timestamp},{host},1,2,3\n",
        f"{timestamp},{host},0.125,87.75,10000.001\n",
        (
            f"{timestamp},{host},9.5,18,27.25\n"
            f"2026-04-17T13:15:15Z,backup-{token},11,22.2,33\n"
        ),
    ]
    invalid_documents = [
        f"{timestamp},bad;host-{token},1,2,3\n",
        f"{timestamp},bad host-{token},1,2,3\n",
        f"{timestamp},bad_host-{token},1,2,3\n",
        f"{timestamp},bad/host-{token},1,2,3\n",
        f"{timestamp},,1,2,3\n",
        f"{timestamp},{host},-1,2,3\n",
        f"{timestamp},{host},1,0,3\n",
        f"{timestamp},{host},1,word-{token},3\n",
        f"{timestamp},{host},1,2,3junk\n",
        f"{timestamp},{host},1,2\n",
        f"{timestamp},{host},1,2,3,4\n",
        (
            f"{timestamp},{host},1,2,3\n"
            f"2026-04-17T13:16:15Z,evil;{token},4,5,6\n"
        ),
    ]

    with tempfile.TemporaryDirectory(prefix="generated-log-check-") as td:
        for index, document in enumerate(valid_documents):
            path = os.path.join(td, f"valid-{token}-{index}.log")
            with open(path, "w", encoding="utf-8") as f:
                f.write(document)
            result = run_sanitiser(path)
            assert result.returncode == 0, (
                f"Generated valid log {index} was rejected with {result.returncode}: "
                f"{result.stderr.decode(errors='replace')}"
            )

        for index, document in enumerate(invalid_documents):
            path = os.path.join(td, f"invalid-{token}-{index}.log")
            with open(path, "w", encoding="utf-8") as f:
                f.write(document)
            result = run_sanitiser(path)
            assert result.returncode == 1, (
                f"Generated invalid log {index} returned {result.returncode}, expected 1"
            )

        missing = os.path.join(td, f"missing-{token}.log")
        result = run_sanitiser(missing)
        assert result.returncode == 1, "A nonexistent input file must be rejected with exit code 1"


def git_run(args, cwd, check=True):
    return subprocess.run(
        ["git"] + args,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=check,
    )


def test_git_repo_and_hook():
    repo_dir = "/home/user/metrics.git"
    assert os.path.isdir(repo_dir), f"Git repo directory {repo_dir} not found"

    config_path = os.path.join(repo_dir, "config")
    assert os.path.isfile(config_path), f"Git config not found at {config_path}"

    with open(config_path, "r") as f:
        config_content = f.read()
    assert "bare = true" in config_content.lower() or "bare = true" in config_content.replace(" ", "").lower(), "Git repository is not bare"

    hook_path = os.path.join(repo_dir, "hooks", "pre-receive")
    assert os.path.isfile(hook_path), f"pre-receive hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"pre-receive hook at {hook_path} is not executable"

    token = secrets.token_hex(8)
    branch = f"verifier-{token}"
    with tempfile.TemporaryDirectory(prefix="git-ingestion-check-") as work:
        git_run(["init"], work)
        git_run(["config", "user.name", "Verifier"], work)
        git_run(["config", "user.email", f"verifier-{token}@example.invalid"], work)
        git_run(["remote", "add", "origin", repo_dir], work)

        log_path = os.path.join(work, f"metrics-{token}.log")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write(f"2026-05-01T10:00:00Z,node-{token},11.5,22,33.25\n")
        git_run(["add", "."], work)
        git_run(["commit", "-m", f"valid initial {token}"], work)
        first_push = git_run(["push", "origin", f"HEAD:refs/heads/{branch}"], work, check=False)
        assert first_push.returncode == 0, (
            "The pre-receive hook rejected a generated valid .log push: " + first_push.stderr
        )

        with open(log_path, "a", encoding="utf-8") as f:
            f.write(f"2026-05-01T10:01:00Z,node-{token}-second,44,55.5,66\n")
        git_run(["add", "."], work)
        git_run(["commit", "-m", f"valid update {token}"], work)
        second_push = git_run(["push", "origin", f"HEAD:refs/heads/{branch}"], work, check=False)
        assert second_push.returncode == 0, (
            "The pre-receive hook rejected a second generated valid .log push: " + second_push.stderr
        )
        accepted_oid = git_run(["rev-parse", "HEAD"], work).stdout.strip()

        evil_path = os.path.join(work, f"injected-{token}.log")
        with open(evil_path, "w", encoding="utf-8") as f:
            f.write(f"2026-05-01T10:02:00Z,node;touch-{token},77,88,99\n")
        git_run(["add", "."], work)
        git_run(["commit", "-m", f"malicious update {token}"], work)
        bad_push = git_run(["push", "origin", f"HEAD:refs/heads/{branch}"], work, check=False)
        assert bad_push.returncode != 0, "The pre-receive hook accepted a malicious generated .log file"

        remote_oid = git_run([f"--git-dir={repo_dir}", "rev-parse", f"refs/heads/{branch}"], work).stdout.strip()
        assert remote_oid == accepted_oid, "The rejected malicious push changed the remote branch"


class ReusableHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def make_handler(marker):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_GET(self):
            body = marker.encode("ascii")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass

    return Handler


def nginx_listener_processes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        port = int(fields[1].split(":")[1], 16)
                        if port == 8080:
                            inodes.add(fields[9])
        except OSError:
            pass

    processes = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        owns_socket = False
        try:
            for fd in os.listdir(fd_dir):
                target = os.readlink(os.path.join(fd_dir, fd))
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owns_socket = True
                    break
            if not owns_socket:
                continue
            with open(f"/proc/{pid}/comm", "r") as f:
                comm = f.read().strip()
            if comm != "nginx":
                continue
            with open(f"/proc/{pid}/status", "r") as f:
                status = f.read()
            uid_line = next(line for line in status.splitlines() if line.startswith("Uid:"))
            effective_uid = int(uid_line.split()[2])
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            processes.append((int(pid), effective_uid, cmdline))
        except (OSError, StopIteration, ValueError):
            continue
    return processes


def test_nginx_setup():
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config not found at {conf_path}"

    with open(conf_path, "r") as f:
        conf_content = f.read()

    assert "8081" in conf_content and "8082" in conf_content, "Nginx config missing upstream servers 8081 and 8082"
    assert "8080" in conf_content, "Nginx config missing listen port 8080"

    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=2):
            pass
    except OSError:
        pytest.fail("Nginx is not listening on port 8080. Is the service running?")

    servers = []
    threads = []
    try:
        for port, marker in ((8081, "backend-A"), (8082, "backend-B")):
            try:
                server = ReusableHTTPServer(("127.0.0.1", port), make_handler(marker))
            except OSError as exc:
                pytest.fail(f"Could not start verifier backend on port {port}: {exc}")
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            servers.append(server)
            threads.append(thread)

        connection = http.client.HTTPConnection("127.0.0.1", 8080, timeout=4)
        responses = []
        try:
            for index in range(6):
                connection.request("GET", f"/verifier-{secrets.token_hex(5)}-{index}")
                response = connection.getresponse()
                body = response.read().decode("ascii", errors="replace")
                assert response.status == 200, f"Nginx proxy returned HTTP {response.status}: {body}"
                responses.append(body)
        finally:
            connection.close()

        assert set(responses) == {"backend-A", "backend-B"}, (
            f"Requests were not proxied to both configured backends: {responses}"
        )
        assert all(responses[i] != responses[i - 1] for i in range(1, len(responses))), (
            f"Backend responses did not follow round-robin order: {responses}"
        )
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
        for thread in threads:
            thread.join(timeout=2)

    listeners = nginx_listener_processes()
    assert listeners, "No Nginx process was found owning the port 8080 listener"
    assert any(uid != 0 for _, uid, _ in listeners), (
        f"No unprivileged Nginx process owns the port 8080 listener: {listeners}"
    )
    assert any(conf_path in cmdline for _, _, cmdline in listeners), (
        f"The running Nginx instance was not started with {conf_path}: {listeners}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
