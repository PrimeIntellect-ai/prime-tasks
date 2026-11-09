#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import socket
import ssl
import subprocess
import time
import urllib.request

import pytest

CERT = "/home/user/cert.pem"
KEY = "/home/user/key.pem"
SOURCE = "/home/user/monitor.c"
BINARY = "/home/user/monitor"
LOG = "/home/user/monitor.log"


def test_certificates_exist():
    """Verify that the generated certificate and key exist."""
    assert os.path.isfile(CERT), f"{CERT} does not exist."
    assert os.path.isfile(KEY), f"{KEY} does not exist."

    decoded = ssl._ssl._test_decode_cert(CERT)
    common_names = [
        value
        for rdn in decoded.get("subject", ())
        for name, value in rdn
        if name == "commonName"
    ]
    assert common_names == ["localhost"], f"Expected certificate CN localhost, got {common_names}."

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", CERT, "-pubkey", "-noout"],
        check=True, capture_output=True, timeout=5
    ).stdout
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", KEY, "-pubout"],
        check=True, capture_output=True, timeout=5
    ).stdout
    assert cert_pub == key_pub, "The certificate and private key do not match."


def _listening_8443_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[1], 16) == 8443 and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            for fd in os.listdir(f"/proc/{pid}/fd"):
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(pid))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def test_tls_proxy_functional():
    """Verify that socat is serving the requested certificate and forwarding port 8443."""
    url = "https://127.0.0.1:8443/"
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.status == 200, f"Expected status 200 from proxy, got {response.status}"
    except Exception as e:
        pytest.fail(f"Failed to connect to TLS proxy at {url} or it did not return a valid response: {e}")

    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="127.0.0.1") as tls:
            served_der = tls.getpeercert(binary_form=True)
    with open(CERT) as f:
        expected_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert served_der == expected_der, "Port 8443 is not serving /home/user/cert.pem."

    pids = _listening_8443_pids()
    assert pids, "No process is listening on port 8443."
    valid_socat = False
    for pid in pids:
        try:
            raw_cmd = open(f"/proc/{pid}/cmdline", "rb").read()
            args = [x.decode(errors="replace") for x in raw_cmd.split(b"\0") if x]
        except (FileNotFoundError, ProcessLookupError):
            continue
        joined = " ".join(args)
        if (args and os.path.basename(args[0]) == "socat"
                and "OPENSSL-LISTEN:8443" in joined
                and "cert=/home/user/cert.pem" in joined
                and "key=/home/user/key.pem" in joined
                and "verify=0" in joined):
            valid_socat = True
            break
    assert valid_socat, "The 8443 listener is not socat configured with the specified certificate, key, and verify=0."


def test_monitor_c_code():
    """Verify that monitor.c exists and contains the required curl elements."""
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    with open(SOURCE) as f:
        content = f.read()
    assert "<curl/curl.h>" in content, "The C program does not include <curl/curl.h>."
    assert "CURLOPT_SSL_VERIFYPEER" in content, "The C program does not seem to configure CURLOPT_SSL_VERIFYPEER."
    assert "CURLOPT_SSL_VERIFYHOST" in content, "The C program does not seem to configure CURLOPT_SSL_VERIFYHOST."


def test_monitor_binary_exists():
    """Verify that the compiled monitor binary exists."""
    assert os.path.isfile(BINARY), f"{BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF binary."


def test_monitor_log():
    """Preserve the required final-state check for three successful requests."""
    assert os.path.isfile(LOG), f"{LOG} does not exist. Did you run the monitor?"
    with open(LOG) as f:
        lines = f.read().splitlines()
    assert len(lines) == 3, f"Expected exactly 3 lines in {LOG}, but found {len(lines)}."
    for i, line in enumerate(lines):
        assert line == "SUCCESS", f"Line {i+1} in {LOG} is '{line}', expected 'SUCCESS'."


def _stop_original_listener():
    pids = _listening_8443_pids()
    for pid in pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline:
        if not _listening_8443_pids():
            return
        time.sleep(0.1)
    for pid in _listening_8443_pids():
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def _exercise_monitor(executable, tag):
    request_log = f"/tmp/{tag}-requests.jsonl"
    ready = f"/tmp/{tag}-ready"
    for path in (request_log, ready, LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    server = subprocess.Popen([
        "python3", "/tmp/controlled_https.py", CERT, KEY, request_log, ready
    ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(ready):
            if server.poll() is not None:
                pytest.fail(f"Controlled HTTPS server failed: {server.stderr.read().decode(errors='replace')}")
            time.sleep(0.05)
        assert os.path.exists(ready), "Controlled HTTPS server did not become ready."

        started = time.monotonic()
        result = subprocess.run([executable], capture_output=True, timeout=15)
        elapsed = time.monotonic() - started
        assert result.returncode == 0, f"{executable} exited with status {result.returncode}."
        assert elapsed >= 1.8, "The monitor did not pause for one second between its three requests."
        time.sleep(0.2)
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()

    with open(request_log) as f:
        requests = [json.loads(line) for line in f if line.strip()]
    assert len(requests) == 3, f"Expected exactly 3 HTTPS requests, observed {len(requests)}."
    assert [(r["method"], r["path"]) for r in requests] == [("GET", "/")] * 3, \
        "The monitor must make exactly three GET requests to /."

    with open(LOG) as f:
        lines = f.read().splitlines()
    assert lines == ["SUCCESS", "FAILURE", "SUCCESS"], \
        f"Monitor output did not reflect the derived HTTP statuses: {lines}."


def test_z_monitor_runtime_behavior():
    """Compile the submitted source and exercise both it and the submitted artifact."""
    _stop_original_listener()

    rebuilt = "/tmp/rebuilt-monitor"
    compilation = subprocess.run(
        ["gcc", "-o", rebuilt, SOURCE, "-lcurl"],
        capture_output=True, timeout=20
    )
    assert compilation.returncode == 0, \
        f"monitor.c does not compile with the required command: {compilation.stderr.decode(errors='replace')}"

    _exercise_monitor(BINARY, "submitted")
    _exercise_monitor(rebuilt, "rebuilt")
TEST_EOF

cat << 'SERVER_EOF' > /tmp/controlled_https.py
import http.server
import json
import ssl
import sys

cert, key, log_path, ready_path = sys.argv[1:]
statuses = [200, 503, 200]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        index = Handler.server.request_count
        status = statuses[index] if index < len(statuses) else 418
        Handler.server.request_count += 1
        with open(log_path, "a") as f:
            f.write(json.dumps({"method": "GET", "path": self.path, "status": status}) + "\n")
        self.send_response(status)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, *args):
        pass

server = http.server.HTTPServer(("127.0.0.1", 8443), Handler)
server.request_count = 0
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
server.socket = ctx.wrap_socket(server.socket, server_side=True)
open(ready_path, "w").close()
server.serve_forever()
SERVER_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
