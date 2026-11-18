#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import signal
import socket
import stat
import subprocess
import threading
import time
import traceback
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ORACLE_PATH = "/opt/oracle/backend_server_oracle"
BACKEND_DIR = "/home/user/app/backend"
AGENT_PATH = os.path.join(BACKEND_DIR, "backend_server")
CONFIG_PATH = "/home/user/app/gateway/config.json"
GATEWAY_DIR = "/home/user/app/gateway"
N_FUZZ = 1000


def expected_transform(value):
    return bytes(b ^ 0x5A for b in base64.b64encode(value.encode("utf-8")))


def kill_listeners(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(victims):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                victims.discard(pid)
        if victims:
            time.sleep(0.5)


def request_gateway(value, timeout=5):
    encoded = urllib.parse.quote(value)
    url = f"http://localhost:8080/api/v1/process?data={encoded}"
    with urllib.request.urlopen(urllib.request.Request(url), timeout=timeout) as response:
        assert response.status == 200, f"Expected HTTP 200, got {response.status}"
        return response.read()


def wait_for_port(port, process, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            out, _ = process.communicate(timeout=1)
            raise AssertionError(f"Gateway exited before listening on port {port}:\n{out}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for port {port}")


def run():
    assert os.path.exists(CONFIG_PATH), f"Config file missing at {CONFIG_PATH}"
    with open(CONFIG_PATH) as f:
        config = json.load(f)
    assert config.get("backend_url") == "http://localhost:9090", "backend_url not correctly updated in config.json"
    assert config.get("rate_limit_rps") == 100, "rate_limit_rps not correctly updated in config.json"

    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    oracle_stat = os.stat(ORACLE_PATH)
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()

    rng = random.Random(42)
    charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"
    inputs = ["".join(rng.choice(charset) for _ in range(rng.randint(16, 256))) for _ in range(N_FUZZ)]
    e2e_input = "EndToEndTestString123!"

    # Preserve the original end-to-end assertion against the services the agent started.
    initial_body = request_gateway(e2e_input)
    assert initial_body == expected_transform(e2e_input), (
        f"Gateway End-to-End Mismatch! Expected {expected_transform(e2e_input)!r}, got {initial_body!r}"
    )

    # Obtain oracle answers and independently validate the shipped oracle before hiding it.
    for value in inputs:
        proc = subprocess.run([ORACLE_PATH, "--cli", value], capture_output=True)
        assert proc.returncode == 0, f"Oracle failed on input: {value}"
        assert proc.stdout == expected_transform(value), f"Oracle produced an unexpected answer for {value!r}"

    kill_listeners(8080)
    kill_listeners(9090)

    # Make the oracle unavailable while rebuilding and exercising the submitted artifacts.
    os.unlink(ORACLE_PATH)
    gateway_proc = None
    probe = None
    try:
        for filename in ("backend_server", "main.o", "algo.o"):
            path = os.path.join(BACKEND_DIR, filename)
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        built = subprocess.run(
            ["make"], cwd=BACKEND_DIR, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=60
        )
        assert built.returncode == 0, f"make failed from a clean build:\n{built.stdout}"
        assert os.path.isfile(AGENT_PATH) and not os.path.islink(AGENT_PATH), "make did not produce a regular backend_server executable"
        assert os.access(AGENT_PATH, os.X_OK), "backend_server is not executable"
        with open(AGENT_PATH, "rb") as f:
            agent_bytes = f.read()
        assert agent_bytes.startswith(b"\\x7fELF"), "backend_server is not an ELF executable"
        assert agent_bytes != oracle_bytes, "backend_server is a byte-identical copy of the reference binary"

        # Compile the submitted C++ sources independently so Makefile tricks cannot replace the implementation.
        source_binary = "/tmp/backend_server_sourcecheck"
        compile_proc = subprocess.run(
            ["g++", "-O2", "main.cpp", "algo.cpp", "-lcrypto_custom", "-o", source_binary],
            cwd=BACKEND_DIR, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=60
        )
        assert compile_proc.returncode == 0, f"Submitted C++ sources do not compile independently:\n{compile_proc.stdout}"

        for value in inputs:
            expected = expected_transform(value)
            agent = subprocess.run([AGENT_PATH, "--cli", value], capture_output=True, timeout=5)
            assert agent.returncode == 0, f"Agent binary failed or crashed on input: {value}"
            assert agent.stdout == expected, f"Backend mismatch for input {value!r}: expected {expected!r}, got {agent.stdout!r}"

            source = subprocess.run([source_binary, "--cli", value], capture_output=True, timeout=5)
            assert source.returncode == 0, f"Binary built directly from submitted sources failed on input: {value}"
            assert source.stdout == expected, f"Submitted algo.cpp mismatch for input {value!r}"

        records = []
        opaque_value = "ProxyProbe-" + str(random.SystemRandom().getrandbits(128))
        opaque_body = os.urandom(48)

        class ProbeHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                parsed = urllib.parse.urlsplit(self.path)
                query = urllib.parse.parse_qs(parsed.query)
                value = query.get("data", [""])[0]
                records.append((parsed.path, value))
                body = opaque_body if value == opaque_value else expected_transform(value)
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, fmt, *args):
                pass

        probe = ThreadingHTTPServer(("127.0.0.1", 9090), ProbeHandler)
        probe_thread = threading.Thread(target=probe.serve_forever, daemon=True)
        probe_thread.start()

        gateway_proc = subprocess.Popen(
            ["go", "run", "main.go"], cwd=GATEWAY_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            start_new_session=True
        )
        wait_for_port(8080, gateway_proc)

        body = request_gateway(e2e_input)
        assert body == expected_transform(e2e_input), "Gateway did not return the backend's transformed response"
        opaque_result = request_gateway(opaque_value)
        assert opaque_result == opaque_body, "Gateway did not relay the actual response from the service on port 9090"
        assert ("/process", e2e_input) in records, "Gateway did not proxy the end-to-end request to /process on port 9090"
        assert ("/process", opaque_value) in records, "Gateway did not proxy the probe request to port 9090"
    finally:
        if gateway_proc is not None:
            try:
                os.killpg(gateway_proc.pid, signal.SIGTERM)
                gateway_proc.wait(timeout=3)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(gateway_proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        if probe is not None:
            probe.shutdown()
            probe.server_close()
        with open(ORACLE_PATH, "wb") as f:
            f.write(oracle_bytes)
        os.chmod(ORACLE_PATH, stat.S_IMODE(oracle_stat.st_mode))


if __name__ == "__main__":
    run()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
