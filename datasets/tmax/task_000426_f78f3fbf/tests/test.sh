#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import socket
import socketserver
import subprocess
import tempfile
import threading
import time

import pytest

CLEAN_DIR = "/home/user/app/corpus/clean"
EVIL_DIR = "/home/user/app/corpus/evil"
LINTER_PATH = "/home/user/app/abi_linter.sh"
ROUTER_PATH = "/home/user/app/router.sh"
LOG_PATH = "/home/user/app/router_access.log"


def run_linter(path):
    return subprocess.run([LINTER_PATH, path], capture_output=True, text=True, timeout=5)


def test_linter_exists_and_executable():
    assert os.path.isfile(LINTER_PATH), f"Linter script {LINTER_PATH} does not exist."
    assert os.access(LINTER_PATH, os.X_OK), f"Linter script {LINTER_PATH} is not executable."


def test_adversarial_corpus_clean():
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert clean_files, f"No files found in clean corpus directory {CLEAN_DIR}."

    modified_clean = []
    for f in clean_files:
        result = run_linter(f)
        if result.returncode != 0 or result.stdout.strip() != "ACCEPT":
            modified_clean.append((os.path.basename(f), result.returncode, result.stdout.strip()))

    if modified_clean:
        details = ", ".join([f"{name} (code {code}, out: {out})" for name, code, out in modified_clean])
        pytest.fail(f"{len(modified_clean)} of {len(clean_files)} clean files rejected: {details}")


def test_adversarial_corpus_evil():
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert evil_files, f"No files found in evil corpus directory {EVIL_DIR}."

    bypassed_evil = []
    for f in evil_files:
        result = run_linter(f)
        if result.returncode != 1 or result.stdout.strip() != "REJECT":
            bypassed_evil.append((os.path.basename(f), result.returncode, result.stdout.strip()))

    if bypassed_evil:
        details = ", ".join([f"{name} (code {code}, out: {out})" for name, code, out in bypassed_evil])
        pytest.fail(f"{len(bypassed_evil)} of {len(evil_files)} evil files bypassed: {details}")


def test_linter_on_fresh_unlabelled_inputs():
    token = secrets.token_hex(8)
    cases = [
        ("import json\nvalue = json.dumps({'x': 'text'})\n", 0, "ACCEPT"),
        (f"import ctypes\nlib = ctypes.CDLL('lib{token}.so')\nlib.send_packet(b'bytes_{token}')\n", 0, "ACCEPT"),
        (f"import ctypes\nlib = ctypes.CDLL('lib{token}.so')\nlib.send_packet(\"text_{token}\".encode('utf-8'))\n", 0, "ACCEPT"),
        (f"import ctypes\nlib = ctypes.CDLL('lib{token}.so')\ndata = 'text_{token}'.encode('utf-8')\nlib.send_packet(data)\n", 0, "ACCEPT"),
        (f"import ctypes\nlib = ctypes.CDLL('lib{token}.so')\nlib.send_packet(\"plain_{token}\")\n", 1, "REJECT"),
        (f"import ctypes\nlib = ctypes.CDLL('lib{token}.so')\nlib.other_call('legacy_{token}')\n", 1, "REJECT"),
    ]
    secrets.SystemRandom().shuffle(cases)
    workdir = tempfile.mkdtemp(prefix=f".abi_check_{token}_", dir="/home/user/app")
    try:
        for source, expected_code, expected_output in cases:
            path = os.path.join(workdir, secrets.token_hex(10) + ".py")
            with open(path, "w", encoding="utf-8") as f:
                f.write(source)
            result = run_linter(path)
            assert result.returncode == expected_code, (path, result.returncode, result.stdout, result.stderr)
            assert result.stdout.strip() == expected_output, (path, result.returncode, result.stdout, result.stderr)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def listener_inodes(ports):
    wanted = {f"{port:04X}" for port in ports}
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A" and fields[1].rsplit(":", 1)[-1].upper() in wanted:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_port_listeners(ports):
    inodes = listener_inodes(ports)
    if not inodes:
        return
    me = os.getpid()
    for pid_name in os.listdir("/proc"):
        if not pid_name.isdigit() or int(pid_name) == me:
            continue
        fd_dir = f"/proc/{pid_name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(pid_name), 9)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    time.sleep(0.2)


class ReusableTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def make_worker(version, received):
    class Worker(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(0.25)
            data = b""
            expected = None
            while len(data) < 1024 * 1024:
                try:
                    chunk = self.request.recv(65536)
                except socket.timeout:
                    break
                if not chunk:
                    break
                data += chunk
                if b"\r\n\r\n" in data:
                    head, body = data.split(b"\r\n\r\n", 1)
                    match = re.search(br"(?i)\r\nContent-Length:\s*(\d+)", b"\r\n" + head)
                    if match:
                        expected = int(match.group(1))
                        if len(body) >= expected:
                            break
            if b"\r\n\r\n" in data:
                head, body = data.split(b"\r\n\r\n", 1)
                match = re.search(br"(?i)\r\nContent-Length:\s*(\d+)", b"\r\n" + head)
                payload = body[:int(match.group(1))] if match else body
            else:
                payload = data
            received[version].append(payload.decode("utf-8", errors="replace"))
            response_body = (f"WORKER{version}:".encode() + payload)
            response = (b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "
                        + str(len(response_body)).encode() + b"\r\nConnection: close\r\n\r\n" + response_body)
            self.request.sendall(response)
    return Worker


def wait_for_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Nothing listened on 127.0.0.1:{port}")


def test_router_end_to_end_and_logging():
    assert os.path.isfile(ROUTER_PATH), f"Router script {ROUTER_PATH} does not exist."
    kill_port_listeners({8080, 9002, 9003})
    received = {2: [], 3: []}
    servers = []
    threads = []
    router = None
    try:
        for version, port in ((2, 9002), (3, 9003)):
            server = ReusableTCPServer(("127.0.0.1", port), make_worker(version, received))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            servers.append(server)
            threads.append(thread)

        with open(LOG_PATH, "w", encoding="utf-8"):
            pass
        router = subprocess.Popen(["bash", ROUTER_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_for_port(8080)

        payloads = {
            2: {"version": 2, "probe": secrets.token_hex(8)},
            3: {"version": 3, "probe": secrets.token_hex(8)},
        }
        for version in (2, 3):
            encoded = json.dumps(payloads[version], separators=(",", ":"))
            result = subprocess.run(
                ["curl", "-sS", "--max-time", "5", "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", encoded, "http://127.0.0.1:8080/"],
                capture_output=True, text=True, timeout=7
            )
            assert result.returncode == 0, result.stderr
            assert f"WORKER{version}:" in result.stdout, result.stdout

        deadline = time.time() + 2
        while time.time() < deadline and (not received[2] or not received[3]):
            time.sleep(0.05)
        for version in (2, 3):
            assert received[version], f"Version {version} request was not forwarded to port {9000 + version}"
            assert any(json.loads(body)["probe"] == payloads[version]["probe"] for body in received[version])

        with open(LOG_PATH, encoding="utf-8") as f:
            lines = [line.rstrip("\n") for line in f if line.strip()]
        for version in (2, 3):
            assert any(re.fullmatch(r"\[[^\]]+\] ROUTED TO " + str(version), line) for line in lines), lines
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
        if router is not None and router.poll() is None:
            router.terminate()
            try:
                router.wait(timeout=1)
            except subprocess.TimeoutExpired:
                router.kill()
        kill_port_listeners({8080, 9002, 9003})
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
