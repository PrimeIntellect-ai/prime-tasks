#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import http.server
import json
import os
import random
import re
import secrets
import signal
import socket
import stat
import subprocess
import threading
import time
import urllib.error
import urllib.request

import pytest

WORKDIR = "/home/user/manifest-operator"
BACKEND_GO = os.path.join(WORKDIR, "backend.go")
PROXY_GO = os.path.join(WORKDIR, "proxy.go")
MONITOR_SH = os.path.join(WORKDIR, "monitor.sh")
BACKEND_LOG = os.path.join(WORKDIR, "backend.log")
PROXY_LOG = os.path.join(WORKDIR, "proxy.log")
BACKEND_BIN = f"/tmp/manifest-backend-{os.getpid()}"
PROXY_BIN = f"/tmp/manifest-proxy-{os.getpid()}"


def listener_pids(port):
    output = subprocess.check_output(["ss", "-ltnp"], text=True, stderr=subprocess.STDOUT)
    pids = set()
    for line in output.splitlines():
        if "LISTEN" in line and re.search(rf":{port}\s", line):
            pids.update(int(x) for x in re.findall(r"pid=(\d+)", line))
    return pids


def port_listening(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.15):
            return True
    except OSError:
        return False


def wait_for(predicate, timeout=12, message="condition was not met"):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    pytest.fail(message)


def stop_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and port_listening(port):
        time.sleep(0.1)
    if port_listening(port):
        for pid in listener_pids(port):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    wait_for(lambda: not port_listening(port), timeout=3,
             message=f"could not stop existing listener on port {port}")
    return pids


def request(body, expected, port=8080):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/apply",
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", "X-Random-Test": secrets.token_hex(6)},
    )
    try:
        with urllib.request.urlopen(req, timeout=4) as response:
            status = response.status
            response.read()
    except urllib.error.HTTPError as exc:
        status = exc.code
        exc.read()
    assert status == expected, f"expected HTTP {expected}, got {status} for body {body!r}"


def read_lines(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return f.read().splitlines()


def test_01_files_exist_executable_and_buildable():
    assert os.path.isdir(WORKDIR), f"Directory {WORKDIR} does not exist."
    assert os.path.isfile(BACKEND_GO), f"{BACKEND_GO} does not exist."
    assert os.path.isfile(PROXY_GO), f"{PROXY_GO} does not exist."
    assert os.path.isfile(MONITOR_SH), f"{MONITOR_SH} does not exist."
    assert os.stat(MONITOR_SH).st_mode & stat.S_IXUSR, f"{MONITOR_SH} is not executable."

    monitor_text = open(MONITOR_SH, encoding="utf-8").read()
    assert "backend.go" in monitor_text, "monitor.sh does not compile/start backend.go"
    assert "proxy.go" in monitor_text, "monitor.sh does not compile/start proxy.go"
    assert re.search(r"\b(ss|netstat|lsof)\b", monitor_text), \
        "monitor.sh does not check listening ports with ss, netstat, or lsof"

    subprocess.run(["go", "build", "-o", BACKEND_BIN, BACKEND_GO], cwd=WORKDIR,
                   check=True, timeout=60)
    subprocess.run(["go", "build", "-o", PROXY_BIN, PROXY_GO], cwd=WORKDIR,
                   check=True, timeout=60)


def test_02_cron_job_configured():
    try:
        output = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab or crontab is empty.")
    expected = "* * * * * /home/user/manifest-operator/monitor.sh"
    assert expected in output, f"Cron job not found. Expected: {expected}"


def test_03_compiled_backend_behavior():
    stop_port(8080)
    stop_port(8081)
    if os.path.exists(BACKEND_LOG):
        os.remove(BACKEND_LOG)

    proc = subprocess.Popen([BACKEND_BIN], cwd=WORKDIR,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for(lambda: port_listening(8081), message="compiled backend.go did not listen on 8081")
        bodies = [
            json.dumps({"nonce": secrets.token_hex(9)}).encode(),
            json.dumps({"data": secrets.token_hex(random.randint(20, 80))}, separators=(",", ":")).encode(),
            b"x" * random.randint(7, 57),
        ]
        for body in bodies:
            request(body, 200, port=8081)
        expected = [f"ACCEPTED: {len(body)} bytes" for body in bodies]
        wait_for(lambda: len(read_lines(BACKEND_LOG)) >= len(expected),
                 message="backend did not write all expected log records")
        assert read_lines(BACKEND_LOG) == expected, "backend.log has incorrect format or body lengths"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
        stop_port(8081)


def test_04_compiled_proxy_randomized_validation_and_forwarding():
    stop_port(8080)
    stop_port(8081)
    if os.path.exists(PROXY_LOG):
        os.remove(PROXY_LOG)

    captured = []

    class CaptureHandler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            captured.append((self.command, self.path, body))
            self.send_response(200)
            self.end_headers()

        def log_message(self, *args):
            pass

    class Server(http.server.ThreadingHTTPServer):
        allow_reuse_address = True

    server = Server(("127.0.0.1", 8081), CaptureHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    proc = subprocess.Popen([PROXY_BIN], cwd=WORKDIR,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for(lambda: port_listening(8080), message="compiled proxy.go did not listen on 8080")
        nonce = secrets.token_hex(12)
        valid = [
            json.dumps({"metadata": {"annotations": {"proxy.local/managed": "true"}}}).encode(),
            json.dumps({"kind": nonce, "metadata": {"annotations": {
                "other": secrets.token_hex(5), "proxy.local/managed": "true"}},
                "spec": {"value": random.randint(1000, 999999)}}).encode(),
            (b'{ "metadata" : { "annotations" : { "proxy.local/managed" : "true" } }, '
             b'"padding" : "' + secrets.token_hex(17).encode() + b'" }'),
        ]
        rejected = [
            json.dumps({"metadata": {"annotations": {}}}).encode(),
            json.dumps({"metadata": {"annotations": {"proxy.local/managed": "false"}}}).encode(),
            json.dumps({"metadata": {"annotations": {"proxy.local/managed": True}}}).encode(),
            json.dumps({"metadata": {"annotations": {"proxy.local/managed": "TRUE"}}}).encode(),
            json.dumps({"metadata": {"proxy.local/managed": "true"}}).encode(),
            json.dumps({"annotations": {"proxy.local/managed": "true"}}).encode(),
            b'{"metadata":{"annotations":{"proxy.local/managed":"true"}',
            b'not-json-' + secrets.token_hex(8).encode(),
            b'null',
        ]
        cases = [(body, 200) for body in valid] + [(body, 403) for body in rejected]
        random.SystemRandom().shuffle(cases)
        for body, status in cases:
            request(body, status)

        wait_for(lambda: len(captured) == len(valid),
                 message="proxy did not forward exactly the accepted requests")
        assert sorted(body for _, _, body in captured) == sorted(valid), \
            "proxy did not forward accepted request bodies unmodified"
        assert all(method == "POST" and path == "/apply" for method, path, _ in captured), \
            "proxy forwarded to the wrong method or backend path"
        wait_for(lambda: len(read_lines(PROXY_LOG)) >= len(rejected),
                 message="proxy did not log all rejected requests")
        assert read_lines(PROXY_LOG) == ["REJECTED"] * len(rejected), \
            "proxy.log must contain exactly one REJECTED line per rejected request"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        stop_port(8080)
        stop_port(8081)


def run_monitor():
    result = subprocess.run([MONITOR_SH], cwd=WORKDIR, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    assert result.returncode == 0, f"monitor.sh failed: {result.stdout}\n{result.stderr}"
    wait_for(lambda: port_listening(8080) and port_listening(8081), timeout=15,
             message="monitor.sh did not make both 8080 and 8081 listen")


def test_05_monitor_starts_services_and_recovers_each_service():
    stop_port(8080)
    stop_port(8081)
    for path in (BACKEND_LOG, PROXY_LOG):
        if os.path.exists(path):
            os.remove(path)

    run_monitor()
    initial_backend = listener_pids(8081)
    initial_proxy = listener_pids(8080)
    assert initial_backend, "Backend service is not listening on port 8081."
    assert initial_proxy, "Proxy service is not listening on port 8080."

    valid_body = json.dumps({
        "nonce": secrets.token_hex(10),
        "metadata": {"annotations": {"proxy.local/managed": "true"}},
    }, separators=(",", ":")).encode()
    request(valid_body, 200)
    wait_for(lambda: f"ACCEPTED: {len(valid_body)} bytes" in read_lines(BACKEND_LOG),
             message="services launched by monitor did not proxy a valid request")

    before = list(read_lines(BACKEND_LOG))
    request(b'{"metadata":{"annotations":{}}}', 403)
    time.sleep(0.3)
    assert read_lines(BACKEND_LOG) == before, "a rejected request was forwarded to the backend"
    assert "REJECTED" in read_lines(PROXY_LOG), "monitor-launched proxy did not log rejection"

    stopped_backend = stop_port(8081)
    assert stopped_backend
    assert port_listening(8080), "stopping backend unexpectedly stopped proxy"
    run_monitor()
    assert listener_pids(8081) and listener_pids(8081).isdisjoint(stopped_backend), \
        "monitor.sh did not restart backend after it stopped"

    stopped_proxy = stop_port(8080)
    assert stopped_proxy
    assert port_listening(8081), "stopping proxy unexpectedly stopped backend"
    run_monitor()
    assert listener_pids(8080) and listener_pids(8080).isdisjoint(stopped_proxy), \
        "monitor.sh did not restart proxy after it stopped"


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
