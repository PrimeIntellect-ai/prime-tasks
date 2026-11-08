#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import http.client
import os
import re
import subprocess
import threading
import time

import pytest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CFG = "/home/user/haproxy.cfg"


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def exe_name(pid):
    try:
        return os.path.basename(os.path.realpath(f"/proc/{pid}/exe"))
    except OSError:
        return ""


def listening_owners(ip, port):
    wanted_ip = "0100007F" if ip == "127.0.0.1" else None
    inodes = set()
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_ip, local_port = fields[1].split(":")
            if fields[3] == "0A" and local_ip == wanted_ip and int(local_port, 16) == port:
                inodes.add(fields[9])

    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(entry))
        except OSError:
            pass
    return owners


def test_haproxy_config_and_process():
    assert os.path.exists(CFG), f"HAProxy config {CFG} does not exist."
    with open(CFG) as f:
        content = f.read()

    # Preserve the original configuration assertions.
    assert "app_front" in content, "Frontend 'app_front' not found in config."
    assert "8080" in content, "Port 8080 not found in config."
    assert "mock_pool" in content, "Backend 'mock_pool' not found in config."
    assert "roundrobin" in content.lower(), "Round-robin load balancing not found in config."
    assert re.search(r"server\s+mock1\s+(127\.0\.0\.1|localhost):8081", content)
    assert re.search(r"server\s+mock2\s+(127\.0\.0\.1|localhost):8082", content)
    assert re.search(r"server\s+mock3\s+(127\.0\.0\.1|localhost):8083", content)
    assert re.search(r"server\s+cloud_api\s+(127\.0\.0\.1|localhost):8084.*\bbackup\b", content)

    validation = subprocess.run(
        ["haproxy", "-c", "-f", CFG], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT
    )
    assert validation.returncode == 0, f"Invalid HAProxy configuration:\n{validation.stdout}"

    try:
        output = subprocess.check_output(
            ["pgrep", "-f", "haproxy.*-f /home/user/haproxy.cfg"]
        ).decode()
        assert output.strip()
    except subprocess.CalledProcessError:
        pytest.fail("HAProxy process is not running with the specified config.")

    owners = listening_owners("127.0.0.1", 8080)
    assert owners, "Nothing is listening on the required HAProxy frontend."
    haproxy_owners = [p for p in owners if exe_name(p) == "haproxy"]
    assert haproxy_owners, "Port 8080 is not owned by a real HAProxy process."
    assert any(CFG in cmdline(p) for p in haproxy_owners), \
        "The HAProxy listener is not using /home/user/haproxy.cfg."


def test_port_forwarder():
    script = "/home/user/forwarder.sh"
    assert os.path.exists(script), f"Forwarder script {script} does not exist."
    assert os.access(script, os.X_OK), f"Forwarder script {script} is not executable."
    assert subprocess.run(["bash", "-n", script]).returncode == 0

    try:
        output = subprocess.check_output(["pgrep", "-f", "socat.*9000.*8080"]).decode()
        assert output.strip()
    except subprocess.CalledProcessError:
        try:
            output = subprocess.check_output(["pgrep", "-f", "forwarder.sh"]).decode()
            assert output.strip()
        except subprocess.CalledProcessError:
            pytest.fail("Neither socat nor forwarder.sh is running.")

    owners = listening_owners("127.0.0.1", 9000)
    assert owners, "Nothing is listening on 127.0.0.1:9000."
    socat_owners = [p for p in owners if exe_name(p) == "socat"]
    assert socat_owners, "Port 9000 is not owned by a real socat process."
    assert any("9000" in cmdline(p) and "8080" in cmdline(p) for p in socat_owners), \
        "The socat listener does not forward port 9000 to port 8080."


def test_cost_optimizer():
    script = "/home/user/cost_optimizer.sh"
    assert os.path.exists(script), f"Cost optimizer script {script} does not exist."
    assert subprocess.run(["bash", "-n", script]).returncode == 0

    try:
        pids = [int(p) for p in subprocess.check_output(
            ["pgrep", "-f", "cost_optimizer.sh"]
        ).decode().split()]
    except subprocess.CalledProcessError:
        pytest.fail("cost_optimizer.sh is not running in the background.")

    real_pids = [p for p in pids if exe_name(p) in ("bash", "sh", "dash") and script in cmdline(p)]
    assert real_pids, "No shell process is actually executing cost_optimizer.sh."

    usage = "/home/user/usage.txt"
    log = "/home/user/scaling.log"

    # Settle any iteration that may have read an earlier value, then start with a clean log.
    with open(usage, "w") as f:
        f.write("STATUS=ACTIVE\n")
    time.sleep(2.6)
    with open(log, "w"):
        pass
    time.sleep(2.4)
    assert os.path.getsize(log) == 0, "Optimizer logs while usage is not exactly STATUS=IDLE."

    with open(usage, "w") as f:
        f.write("STATUS=IDLE\n")

    expected = "FinOps: Scaled down mock3"
    event_times = []
    last_count = 0
    deadline = time.monotonic() + 7.0
    while time.monotonic() < deadline and len(event_times) < 2:
        with open(log) as f:
            lines = f.read().splitlines()
        assert all(line == expected for line in lines), "Optimizer appended an incorrect log line."
        if len(lines) > last_count:
            now = time.monotonic()
            event_times.extend([now] * (len(lines) - last_count))
            last_count = len(lines)
        time.sleep(0.05)

    with open(usage, "w") as f:
        f.write("STATUS=ACTIVE\n")

    assert len(event_times) >= 2, "Optimizer did not continuously process STATUS=IDLE."
    interval = event_times[1] - event_times[0]
    assert 1.5 <= interval <= 3.5, f"Optimizer iterations are not approximately 2 seconds apart ({interval:.2f}s)."
    assert all(os.path.exists(f"/proc/{p}") for p in real_pids), \
        "The cost optimizer is not still running in the background."


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        bodies = {8081: b"MOCK1", 8082: b"MOCK2", 8083: b"MOCK3", 8084: b"CLOUD"}
        body = bodies[self.server.server_port]
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


class ReusableServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def request_legacy(timeout=2):
    connection = http.client.HTTPConnection("127.0.0.1", 9000, timeout=timeout)
    try:
        connection.request("GET", "/", headers={"Connection": "close"})
        response = connection.getresponse()
        body = response.read().decode()
        assert response.status == 200, f"Unexpected HTTP status {response.status}"
        return body
    finally:
        connection.close()


def test_network_integration_round_robin_and_backup_failover():
    servers = {}
    threads = []
    try:
        for port in (8081, 8082, 8083, 8084):
            servers[port] = ReusableServer(("127.0.0.1", port), Handler)
            thread = threading.Thread(target=servers[port].serve_forever, daemon=True)
            thread.start()
            threads.append(thread)

        time.sleep(2.5)

        # Wait until HAProxy has recognized all primary servers as available.
        observed = set()
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and observed != {"MOCK1", "MOCK2", "MOCK3"}:
            try:
                body = request_legacy()
                assert body in {"MOCK1", "MOCK2", "MOCK3"}, \
                    "The backup server was used while primary servers were healthy."
                observed.add(body)
            except (OSError, http.client.HTTPException):
                time.sleep(0.2)
        assert observed == {"MOCK1", "MOCK2", "MOCK3"}, \
            f"Traffic did not reach all three primary mocks: {observed}"

        responses = [request_legacy() for _ in range(9)]
        counts = collections.Counter(responses)
        assert "CLOUD" not in counts, "Backup was used while primary servers were healthy."
        assert counts == {"MOCK1": 3, "MOCK2": 3, "MOCK3": 3}, \
            f"Backend is not distributing requests round-robin: {responses}"

        # Remove every primary and require HAProxy to detect the outage and use only backup.
        for port in (8081, 8082, 8083):
            servers[port].shutdown()
            servers[port].server_close()
            del servers[port]

        deadline = time.monotonic() + 12
        body = None
        while time.monotonic() < deadline:
            try:
                body = request_legacy(timeout=1.5)
                if body == "CLOUD":
                    break
            except (OSError, http.client.HTTPException, AssertionError):
                pass
            time.sleep(0.25)
        assert body == "CLOUD", "HAProxy did not fail over to cloud_api after all primaries stopped."
        assert [request_legacy() for _ in range(3)] == ["CLOUD"] * 3
    finally:
        for server in list(servers.values()):
            server.shutdown()
            server.server_close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
