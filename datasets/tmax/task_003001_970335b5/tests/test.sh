#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import json
import urllib.request
import ssl
import socket
import time
import secrets
import threading
import http.server
import pytest

WEBHOOK_DIR = "/home/user/webhook"
CERT_FILE = os.path.join(WEBHOOK_DIR, "cert.pem")
KEY_FILE = os.path.join(WEBHOOK_DIR, "key.pem")
SERVER_SCRIPT = os.path.join(WEBHOOK_DIR, "server.py")
ALERTS_LOG = os.path.join(WEBHOOK_DIR, "alerts.log")
MONITOR_SCRIPT = "/home/user/monitor.sh"
CRON_CONF = "/home/user/cron.conf"


def kill_listeners(ports):
    wanted = set(ports)
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    port = int(local.rsplit(":", 1)[1], 16)
                    if state == "0A" and port in wanted:
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
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, 0)
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    time.sleep(0.3)


def insecure_post(payload):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(
        "https://127.0.0.1:8443/alert", data=payload, method="POST"
    )
    req.add_header("Content-Type", "application/json")
    return urllib.request.urlopen(req, context=ctx, timeout=5)


def wait_for_https(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with insecure_post(b'{"service":"startup_probe","status":"down"}') as response:
                if response.getcode() == 200:
                    return
        except Exception:
            time.sleep(0.15)
    pytest.fail("server.py did not start a working HTTPS server on 127.0.0.1:8443")


def test_certificates_exist():
    assert os.path.isfile(CERT_FILE), f"Certificate file {CERT_FILE} is missing."
    assert os.path.isfile(KEY_FILE), f"Key file {KEY_FILE} is missing."


def test_certificate_properties_and_key_match():
    decoded = ssl._ssl._test_decode_cert(CERT_FILE)
    common_names = [value for rdn in decoded["subject"] for key, value in rdn if key == "commonName"]
    assert common_names == ["localhost"], "Certificate Common Name must be localhost."
    assert decoded["subject"] == decoded["issuer"], "Certificate is not self-signed."

    not_before = ssl.cert_time_to_seconds(decoded["notBefore"])
    not_after = ssl.cert_time_to_seconds(decoded["notAfter"])
    validity_days = (not_after - not_before) / 86400
    assert 364.9 <= validity_days <= 365.1, "Certificate must be valid for 365 days."

    verify = subprocess.run(
        ["openssl", "verify", "-CAfile", CERT_FILE, CERT_FILE],
        text=True, capture_output=True
    )
    assert verify.returncode == 0, f"Certificate self-signature is invalid: {verify.stderr}"

    cert_modulus = subprocess.check_output(
        ["openssl", "x509", "-in", CERT_FILE, "-noout", "-modulus"], text=True
    ).strip()
    key_modulus = subprocess.check_output(
        ["openssl", "rsa", "-in", KEY_FILE, "-noout", "-modulus"],
        text=True, stderr=subprocess.STDOUT
    ).strip()
    assert cert_modulus == key_modulus, "cert.pem and key.pem do not form a pair."

    pubkey = subprocess.Popen(
        ["openssl", "x509", "-in", CERT_FILE, "-pubkey", "-noout"],
        stdout=subprocess.PIPE
    )
    key_info = subprocess.check_output(
        ["openssl", "pkey", "-pubin", "-text", "-noout"], stdin=pubkey.stdout, text=True
    )
    pubkey.stdout.close()
    pubkey.wait()
    assert "2048 bit" in key_info, "Certificate does not contain a 2048-bit RSA key."
    assert "RSA Public-Key" in key_info or "Modulus:" in key_info, "Certificate key is not RSA."


def test_webhook_script_exists():
    assert os.path.isfile(SERVER_SCRIPT), f"Server script {SERVER_SCRIPT} is missing."
    with open(SERVER_SCRIPT, "r") as f:
        content = f.read()
    assert "ssl" in content, "Server script does not seem to import 'ssl'."


def test_monitor_script_executable_and_content():
    assert os.path.isfile(MONITOR_SCRIPT), f"Monitor script {MONITOR_SCRIPT} is missing."
    st = os.stat(MONITOR_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{MONITOR_SCRIPT} is not executable."
    with open(MONITOR_SCRIPT, "r") as f:
        content = f.read()
    assert "curl" in content, "Monitor script does not contain 'curl'."
    assert "8443/alert" in content, "Monitor script does not post to the webhook on 8443."


def test_cron_job_configured():
    try:
        output = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it configured?")
    assert "* * * * * /home/user/monitor.sh" in output, "Crontab does not contain the expected cron job for monitor.sh."
    assert os.path.isfile(CRON_CONF), f"Cron configuration file {CRON_CONF} is missing."
    with open(CRON_CONF) as f:
        assert "* * * * * /home/user/monitor.sh" in f.read(), "cron.conf lacks the required schedule."


def test_alerts_log_content():
    assert os.path.isfile(ALERTS_LOG), f"Alerts log {ALERTS_LOG} is missing."
    with open(ALERTS_LOG, "r") as f:
        lines = f.read().strip().splitlines()
    assert len(lines) >= 1, "Alerts log is empty."
    try:
        last_alert = json.loads(lines[-1])
    except json.JSONDecodeError:
        pytest.fail("The last line in alerts.log is not valid JSON.")
    assert last_alert.get("service") == "service_8003", "Expected alert for 'service_8003'."
    assert last_alert.get("status") == "down", "Expected status 'down'."


def test_webhook_server_running():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    data = json.dumps({"service": "test_service", "status": "down"}).encode("utf-8")
    req = urllib.request.Request("https://127.0.0.1:8443/alert", data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.getcode() == 200, "Webhook server did not return HTTP 200 OK."
    except Exception as e:
        pytest.fail(f"Failed to connect and POST to the webhook server on 8443: {e}")


def test_execute_server_and_raw_logging():
    kill_listeners([8443])
    try:
        os.unlink(ALERTS_LOG)
    except FileNotFoundError:
        pass

    subprocess.Popen(
        ["runuser", "-u", "user", "--", "python3", SERVER_SCRIPT],
        cwd=WEBHOOK_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    wait_for_https()

    # Remove the startup probe while retaining a user-owned, writable log.
    with open(ALERTS_LOG, "r+") as f:
        f.truncate(0)

    nonce = secrets.token_hex(12)
    raw = ('{  "service" : "raw_%s", "status" : "down"  }' % nonce).encode("utf-8")
    with insecure_post(raw) as response:
        assert response.getcode() == 200

    deadline = time.time() + 3
    logged = b""
    while time.time() < deadline:
        if os.path.isfile(ALERTS_LOG):
            with open(ALERTS_LOG, "rb") as f:
                logged = f.read()
            if logged:
                break
        time.sleep(0.05)
    assert logged == raw + b"\n", "server.py did not append the exact raw POST body followed by one newline."

    expected_der = ssl.PEM_cert_to_DER_cert(open(CERT_FILE).read())
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as sock:
        with ctx.wrap_socket(sock, server_hostname="localhost") as tls_sock:
            presented_der = tls_sock.getpeercert(binary_form=True)
    assert presented_der == expected_der, "The executed server.py is not serving cert.pem."


def test_execute_monitor_against_derived_health_states():
    subprocess.run(["service", "cron", "stop"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    kill_listeners([8001, 8002, 8003])

    down_ports = set(secrets.choice([
        (8001,), (8002,), (8003,), (8001, 8002), (8001, 8003), (8002, 8003)
    ]))
    statuses = {port: (503 if port in down_ports else 200) for port in (8001, 8002, 8003)}
    requests = {port: [] for port in statuses}
    servers = []

    for port in (8001, 8002, 8003):
        expected_status = statuses[port]
        request_log = requests[port]

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                request_log.append((self.command, self.path))
                code = expected_status if self.path == "/health" else 404
                self.send_response(code)
                self.end_headers()
                self.wfile.write(b"OK" if code == 200 else b"DOWN")
            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        servers.append(server)

    with open(ALERTS_LOG, "r+") as f:
        f.truncate(0)

    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", MONITOR_SCRIPT],
            text=True, capture_output=True, timeout=20
        )
        assert result.returncode == 0, f"monitor.sh failed: {result.stderr}"

        deadline = time.time() + 4
        lines = []
        while time.time() < deadline:
            with open(ALERTS_LOG, "rb") as f:
                lines = f.read().splitlines()
            if len(lines) >= len(down_ports):
                break
            time.sleep(0.05)

        for port in (8001, 8002, 8003):
            assert ("GET", "/health") in requests[port], f"monitor.sh did not GET port {port}/health."

        expected = {
            ('{"service": "service_%d", "status": "down"}' % port).encode("utf-8")
            for port in down_ports
        }
        assert len(lines) == len(expected), "monitor.sh emitted an incorrect number of alerts."
        assert set(lines) == expected, "monitor.sh did not emit the exact required JSON for the derived unhealthy services."
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
