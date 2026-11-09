#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid
from http.server import HTTPServer, BaseHTTPRequestHandler

BASE = "http://127.0.0.1:8000"


def request(path, method="GET", body=None, deploy_env=None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    if deploy_env is not None:
        req.add_header("X-Deploy-Env", deploy_env)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            raw = response.read().decode("utf-8")
            parsed = json.loads(raw) if raw else None
            return response.status, parsed, raw
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = None
        return exc.code, parsed, raw


def green_post(path, body=None):
    return request(path, method="POST", body=body, deploy_env="green")


def green_get(path):
    return request(path, deploy_env="green")


def listening_socket_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table, "r") as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address = fields[1]
                state = fields[3]
                if state == "0A" and int(local_address.rsplit(":", 1)[1], 16) == port:
                    inodes.add(fields[9])
    return inodes


def socket_owner_pids(inodes):
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def test_deployment_log():
    log_path = "/home/user/deployment.log"
    assert os.path.isfile(log_path), f"File not found: {log_path}"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "DEPLOYMENT READY" in content, f"Expected 'DEPLOYMENT READY' in {log_path}"


def test_nginx_configuration_and_process():
    config_path = "/home/user/nginx.conf"
    data_dir = "/home/user/nginx_data"
    assert os.path.isfile(config_path), f"File not found: {config_path}"
    assert os.path.isdir(data_dir), f"Directory not found: {data_dir}"

    checked = subprocess.run(
        ["nginx", "-T", "-c", config_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert checked.returncode == 0, f"nginx configuration is invalid:\n{checked.stdout}"

    # Remove comments before checking that required directives are active.
    active = "\n".join(line.split("#", 1)[0] for line in checked.stdout.splitlines())
    assert re.search(r"\blisten\s+127\.0\.0\.1:8000(?:\s|;)", active), "Missing required listen directive"
    assert "http_x_deploy_env" in active.lower(), "Configuration does not inspect X-Deploy-Env"
    assert re.search(r"127\.0\.0\.1:8081", active), "Green backend is not configured"
    assert re.search(r"127\.0\.0\.1:8080", active), "Legacy backend is not configured"

    required_paths = (
        "pid",
        "error_log",
        "access_log",
        "client_body_temp_path",
        "proxy_temp_path",
        "fastcgi_temp_path",
        "uwsgi_temp_path",
        "scgi_temp_path",
    )
    for directive in required_paths:
        pattern = rf"\b{directive}\s+[\"']?/home/user/nginx_data/"
        assert re.search(pattern, active), f"{directive} must point inside /home/user/nginx_data/"

    # Preserve the original open-port assertion, while also proving nginx owns it.
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.settimeout(2)
        s.connect(("127.0.0.1", 8000))
    except OSError as exc:
        raise AssertionError("Nginx is not listening on 127.0.0.1:8000") from exc
    finally:
        s.close()

    inodes = listening_socket_inodes(8000)
    assert inodes, "No listening socket was found for port 8000"
    owners = socket_owner_pids(inodes)
    assert owners, "Could not identify the process listening on port 8000"

    nginx_owners = []
    uses_requested_config = False
    for pid in owners:
        try:
            with open(f"/proc/{pid}/comm", "r") as f:
                comm = f.read().strip()
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
            executable = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if comm == "nginx" or executable == "nginx":
            nginx_owners.append(pid)
            if config_path in cmdline:
                uses_requested_config = True

    assert nginx_owners, "Port 8000 is not owned by an nginx process"
    assert uses_requested_config, "The nginx listener was not started with /home/user/nginx.conf"


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


class DummyLegacyHandler(BaseHTTPRequestHandler):
    marker = ""

    def _reply(self):
        payload = json.dumps({"legacy": self.marker}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = _reply
    do_POST = _reply

    def log_message(self, format, *args):
        pass


def drain_cache(limit=256):
    for _ in range(limit):
        status, _, _ = green_post("/evict")
        if status == 404:
            return
        assert status == 200, f"Unexpected status {status} while draining cache"
    raise AssertionError("Cache did not become empty after 256 evictions")


def test_routing_and_green_logic():
    marker = "legacy-" + uuid.uuid4().hex
    DummyLegacyHandler.marker = marker
    legacy_server = ReusableHTTPServer(("127.0.0.1", 8080), DummyLegacyHandler)
    server_thread = threading.Thread(target=legacy_server.serve_forever, daemon=True)
    server_thread.start()
    time.sleep(0.3)

    try:
        # Original fallback assertion, strengthened with an unpredictable marker.
        status, body, raw = request("/get/test")
        assert status == 200 and "legacy" in raw, "Expected response from legacy server when header is missing"
        assert body == {"legacy": marker}, "Missing-header traffic did not reach the test legacy backend"

        # Any value other than exactly 'green' must also use legacy.
        for header in ("blue", "GREEN", "green-" + uuid.uuid4().hex):
            status, body, _ = request("/get/" + uuid.uuid4().hex, deploy_env=header)
            assert status == 200 and body == {"legacy": marker}, f"Header value {header!r} was not routed to legacy"

        drain_cache()

        # Preserve the original fixed sequence and assertions.
        for item in (
            {"key": "A", "value": "valA", "priority": 10},
            {"key": "B", "value": "valB", "priority": 10},
            {"key": "C", "value": "valC", "priority": 5},
            {"key": "D", "value": "valD", "priority": 5},
        ):
            status, _, _ = green_post("/put", item)
            assert status == 200, f"PUT failed for {item['key']}"

        status, evict1, _ = green_post("/evict")
        assert status == 200 and evict1 is not None and "key" in evict1, "Evict response missing key"
        assert evict1["key"] == "D", f"Expected to evict 'D', got {evict1['key']}"
        assert evict1.get("value") == "valD", "Evict returned the wrong value for D"

        status, evict2, _ = green_post("/evict")
        assert status == 200 and evict2 is not None and "key" in evict2, "Evict response missing key"
        assert evict2["key"] == "C", f"Expected to evict 'C', got {evict2['key']}"
        assert evict2.get("value") == "valC", "Evict returned the wrong value for C"

        status, get_a, _ = green_get("/get/A")
        assert status == 200 and get_a is not None and "value" in get_a, "Get A response missing value"
        assert get_a["value"] == "valA", f"Expected value 'valA', got {get_a['value']}"

        drain_cache()

        # Exercise a fresh, unpredictable operation sequence. Expected answers are
        # derived from the required priority/LIFO model rather than hardcoded.
        rng = random.SystemRandom()
        prefix = uuid.uuid4().hex
        keys = [f"k_{prefix}_{i}" for i in range(9)]
        priorities = rng.sample(range(-10000, 10001), 3)
        priorities.sort()
        model = {}
        sequence = 0

        def modeled_put(key, value, priority):
            nonlocal sequence
            status, _, _ = green_post("/put", {"key": key, "value": value, "priority": priority})
            assert status == 200, f"PUT failed for randomized key {key}"
            sequence += 1
            model[key] = {"value": value, "priority": priority, "sequence": sequence}

        shuffled = keys[:]
        rng.shuffle(shuffled)
        for i, key in enumerate(shuffled):
            modeled_put(key, f"v_{uuid.uuid4().hex}", priorities[i % 3])

        # Updates test changed values, changed priorities, and recency within ties.
        update_order = rng.sample(keys, 5)
        for i, key in enumerate(update_order):
            modeled_put(key, f"updated_{uuid.uuid4().hex}", priorities[(i + 1) % 3])

        for key, expected in model.items():
            status, body, _ = green_get("/get/" + key)
            assert status == 200, f"GET failed for existing key {key}"
            assert body == {"value": expected["value"]}, f"GET returned wrong value for {key}"

        missing = "missing_" + uuid.uuid4().hex
        status, _, _ = green_get("/get/" + missing)
        assert status == 404, "GET of an unknown key must return HTTP 404"

        while model:
            expected_key, expected = min(
                model.items(), key=lambda pair: (pair[1]["priority"], -pair[1]["sequence"])
            )
            status, body, _ = green_post("/evict")
            assert status == 200, "Evict unexpectedly failed on a non-empty cache"
            assert body == {"key": expected_key, "value": expected["value"]}, (
                f"Wrong eviction: expected {expected_key!r}/{expected['value']!r}, got {body!r}"
            )
            del model[expected_key]
            status, _, _ = green_get("/get/" + expected_key)
            assert status == 404, "Evicted key is still retrievable"

        status, _, _ = green_post("/evict")
        assert status == 404, "Evict on an empty cache must return HTTP 404"
    finally:
        legacy_server.shutdown()
        legacy_server.server_close()
        server_thread.join(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
