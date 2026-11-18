#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import pwd
import queue
import random
import re
import signal
import socket
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def test_nginx_config():
    config_path = "/home/user/nginx_alert.conf"
    assert os.path.isfile(config_path), f"Nginx config not found at {config_path}"
    with open(config_path, "r") as f:
        content = f.read()

    # Preserve the original configuration assertion.
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:3000/?;", content), \
        "proxy_pass directive pointing to http://127.0.0.1:3000 not found in config"


def _listener_inodes(address, port):
    wanted_address = socket.inet_aton(address)[::-1].hex().upper()
    wanted_port = f"{port:04X}"
    inodes = set()

    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, local_port = fields[1].split(":")
            state = fields[3]
            if local_address == wanted_address and local_port == wanted_port and state == "0A":
                inodes.add(fields[9])
    return inodes


def _processes_holding_socket(inodes):
    holders = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    holders.append(int(pid))
                    break
        except OSError:
            continue
    return holders


def test_nginx_listening_and_forwarding():
    # Preserve the original listening assertion.
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex(("127.0.0.1", 8080))
    sock.close()
    assert result == 0, "Nothing is listening on 127.0.0.1:8080"

    inodes = _listener_inodes("127.0.0.1", 8080)
    assert inodes, "No listener is bound specifically to 127.0.0.1:8080"

    holders = _processes_holding_socket(inodes)
    assert holders, "Could not identify the process listening on 127.0.0.1:8080"
    assert any(os.path.realpath(f"/proc/{pid}/exe") == "/usr/sbin/nginx" for pid in holders), \
        "The listener on 127.0.0.1:8080 is not Nginx"

    received = queue.Queue()
    token = os.urandom(20).hex()
    request_path = "/verifier-proxy-check/" + os.urandom(12).hex()
    request_body = ("body-" + os.urandom(12).hex()).encode()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            received.put((self.path, body, self.headers.get("X-Verifier-Token")))
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(token.encode())

        def log_message(self, *args):
            pass

    try:
        server = ThreadingHTTPServer(("127.0.0.1", 3000), Handler)
    except OSError as exc:
        raise AssertionError(f"Cannot start the controlled dashboard backend on 127.0.0.1:3000: {exc}")

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
        conn.request("POST", request_path, body=request_body,
                     headers={"X-Verifier-Token": token, "Content-Type": "application/octet-stream"})
        response = conn.getresponse()
        response_body = response.read().decode()
        conn.close()

        assert response.status == 200, f"Nginx returned HTTP {response.status} instead of forwarding the request"
        assert response_body == token, "Response did not come from the controlled backend on port 3000"
        forwarded_path, forwarded_body, forwarded_token = received.get(timeout=2)
        assert forwarded_path == request_path, "Nginx did not forward the original request path"
        assert forwarded_body == request_body, "Nginx did not forward the original request body"
        assert forwarded_token == token, "Nginx did not forward the request headers"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def _kill_agent_helpers(uid):
    # Verification happens after the agent has finished. Remove user-owned helper
    # processes so alerter.py cannot delegate to a pre-started oracle service.
    for pid_text in os.listdir("/proc"):
        if not pid_text.isdigit() or int(pid_text) == os.getpid():
            continue
        try:
            with open(f"/proc/{pid_text}/status", "r") as f:
                status = f.read()
            match = re.search(r"^Uid:\s+(\d+)", status, re.MULTILINE)
            if match and int(match.group(1)) == uid:
                os.kill(int(pid_text), signal.SIGKILL)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass


def _expected(args):
    cpu, mem, disk, net, err = args
    score = cpu * 20 + mem * 15 + disk * 5 + net + err * 100
    if score > 5000 and err > 5:
        return "CRITICAL"
    if score > 3000 or err > 10:
        return "WARNING"
    return "OK"


def test_fuzz_equivalence():
    oracle_path = "/app/legacy_alerter"
    agent_script = "/home/user/alerter.py"

    # Preserve the original artifact assertions before making the oracle
    # unavailable to the submitted program.
    assert os.path.isfile(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"

    user = pwd.getpwnam("user")
    _kill_agent_helpers(user.pw_uid)

    # The oracle was available for reverse engineering, but must not be callable
    # by alerter.py during verification.
    os.chmod(oracle_path, 0)

    trace_dir = tempfile.mkdtemp(prefix="alerter-trace-")
    os.chown(trace_dir, user.pw_uid, user.pw_gid)
    os.chmod(trace_dir, 0o700)
    trace_path = os.path.join(trace_dir, "trace.log")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    random.seed(42)
    cases = [[random.randint(0, 100) for _ in range(5)] for _ in range(5000)]
    cases.extend([
        [0, 0, 0, 0, 0], [100, 100, 100, 100, 100],
        [100, 100, 100, 100, 5], [0, 0, 0, 0, 11],
        [100, 100, 0, 0, 0], [0, 0, 0, 0, 10],
    ])

    for values in cases:
        args = [str(value) for value in values]
        command = [
            "/usr/bin/strace", "-f", "-qq",
            "-e", "trace=execve,execveat,connect",
            "-o", trace_path,
            "/usr/bin/python3", agent_script, *args,
        ]
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=5,
            cwd="/home/user",
            preexec_fn=demote,
        )

        assert result.returncode == 0, f"Agent failed on input: {' '.join(args)}\n{result.stderr}"
        assert result.stdout.strip() == _expected(values), (
            f"Mismatch on input: {' '.join(args)}\n"
            f"Expected: '{_expected(values)}'\n"
            f"Agent output: '{result.stdout.strip()}'"
        )

        with open(trace_path, "r", errors="replace") as f:
            trace = f.read()
        exec_calls = re.findall(r"\bexecve(?:at)?\(", trace)
        assert len(exec_calls) == 1, \
            f"alerter.py delegated to another executable on input: {' '.join(args)}"
        assert not re.search(r"\bconnect\(", trace), \
            f"alerter.py attempted to delegate over a socket on input: {' '.join(args)}"


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
