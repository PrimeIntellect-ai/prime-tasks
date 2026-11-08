#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import time
import ssl
import shutil
import secrets
import tempfile
import subprocess
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta
import pytest

PROVISION_SCRIPT = "/home/user/provision.py"
GATEWAY_SCRIPT = "/home/user/gateway.py"
CONFIG_FILE = "/home/user/vm.conf"
SSL_CERT = "/home/user/ssl/cert.pem"
SSL_KEY = "/home/user/ssl/key.pem"
METRICS_FILE = "/home/user/web/metrics.json"


def run_provision(env=None):
    result = subprocess.run(
        ["python3", PROVISION_SCRIPT],
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, f"provision.py failed to execute. stderr: {result.stderr}"


def read_metrics():
    assert os.path.exists(METRICS_FILE), f"Metrics file {METRICS_FILE} was not generated."
    with open(METRICS_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{METRICS_FILE} does not contain valid JSON.")


def fetch_gateway_metrics():
    server_process = subprocess.Popen(
        ["python3", GATEWAY_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        time.sleep(2)
        if server_process.poll() is not None:
            stdout, stderr = server_process.communicate()
            pytest.fail(f"gateway.py exited prematurely. stderr: {stderr.decode('utf-8')}")

        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        url = "https://127.0.0.1:8443/metrics.json"
        try:
            with urllib.request.urlopen(url, context=ctx, timeout=5) as response:
                assert response.status == 200, f"Expected HTTP 200, got {response.status}"
                try:
                    return json.loads(response.read().decode("utf-8"))
                except json.JSONDecodeError:
                    pytest.fail("Response from gateway is not valid JSON.")
        except urllib.error.URLError as e:
            pytest.fail(f"Failed to connect to gateway server: {e}")
    finally:
        server_process.terminate()
        try:
            server_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server_process.kill()
            server_process.wait(timeout=5)


def assert_certificate_properties():
    assert os.path.isfile(SSL_CERT), f"SSL certificate {SSL_CERT} was not generated."
    assert os.path.isfile(SSL_KEY), f"SSL key {SSL_KEY} was not generated."

    decoded = ssl._ssl._test_decode_cert(SSL_CERT)
    common_names = [
        value
        for rdn in decoded.get("subject", ())
        for key, value in rdn
        if key == "commonName"
    ]
    assert common_names == ["localhost"], f"Expected certificate CN localhost, got {common_names}"
    assert decoded.get("issuer") == decoded.get("subject"), "Certificate is not self-signed."

    cert_text = subprocess.run(
        ["openssl", "x509", "-in", SSL_CERT, "-noout", "-text", "-dates"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert "Public Key Algorithm: rsaEncryption" in cert_text, "Certificate key is not RSA."

    dates = {}
    for line in cert_text.splitlines():
        line = line.strip()
        if line.startswith("notBefore=") or line.startswith("notAfter="):
            key, value = line.split("=", 1)
            dates[key] = datetime.strptime(value, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
    assert set(dates) == {"notBefore", "notAfter"}, "Could not read certificate validity dates."
    assert dates["notAfter"] - dates["notBefore"] >= timedelta(days=30), "Certificate is valid for less than 30 days."
    now = datetime.now(timezone.utc)
    assert dates["notBefore"] <= now + timedelta(minutes=1)
    assert dates["notAfter"] > now

    key_check = subprocess.run(
        ["openssl", "pkey", "-in", SSL_KEY, "-noout", "-check"],
        capture_output=True,
        text=True,
    )
    assert key_check.returncode == 0, f"Invalid private key: {key_check.stderr}"
    verify = subprocess.run(
        ["openssl", "verify", "-CAfile", SSL_CERT, SSL_CERT],
        capture_output=True,
        text=True,
    )
    assert verify.returncode == 0, f"Certificate is not a valid self-signed certificate: {verify.stderr}"


def test_provision_script_exists():
    assert os.path.exists(PROVISION_SCRIPT), f"{PROVISION_SCRIPT} does not exist."
    assert os.path.isfile(PROVISION_SCRIPT), f"{PROVISION_SCRIPT} is not a file."


def test_run_provision_script():
    run_provision()


def test_ssl_certificates_generated():
    assert os.path.exists(SSL_CERT), f"SSL certificate {SSL_CERT} was not generated."
    assert os.path.exists(SSL_KEY), f"SSL key {SSL_KEY} was not generated."
    assert_certificate_properties()


def test_metrics_json_content():
    metrics = read_metrics()
    assert "vm" in metrics, "Key 'vm' missing in metrics.json"
    assert metrics["vm"] == "production-db-01", f"Expected vm 'production-db-01', got {metrics['vm']}"
    assert "vnc_port" in metrics, "Key 'vnc_port' missing in metrics.json"
    assert metrics["vnc_port"] == 5912, f"Expected vnc_port 5912, got {metrics['vnc_port']}"
    assert "status" in metrics, "Key 'status' missing in metrics.json"
    assert metrics["status"] == "running", f"Expected status 'running', got {metrics['status']}"


def test_gateway_server():
    assert os.path.exists(GATEWAY_SCRIPT), f"{GATEWAY_SCRIPT} was not generated."
    metrics = fetch_gateway_metrics()
    assert metrics.get("vm") == "production-db-01", "Gateway response missing or incorrect 'vm' key."
    assert metrics.get("vnc_port") == 5912, "Gateway response missing or incorrect 'vnc_port' key."


def test_randomized_configs_and_openssl_subprocess():
    display1 = secrets.randbelow(80) + 1
    while display1 == 12:
        display1 = secrets.randbelow(80) + 1
    name1 = "vm-" + secrets.token_hex(8)

    shutil.rmtree("/home/user/ssl", ignore_errors=True)
    shutil.rmtree("/home/user/web", ignore_errors=True)
    try:
        os.unlink(GATEWAY_SCRIPT)
    except FileNotFoundError:
        pass

    with open(CONFIG_FILE, "w") as f:
        f.write(f"VM_NAME={name1}\nVNC_DISPLAY=:{display1}\nMEMORY=1024M\n")

    with tempfile.TemporaryDirectory() as td:
        audit_log = os.path.join(td, "subprocess.log")
        sitecustomize = os.path.join(td, "sitecustomize.py")
        with open(sitecustomize, "w") as f:
            f.write('import os, sys\n')
            f.write('def audit(event, args):\n')
            f.write('    if event == "subprocess.Popen":\n')
            f.write('        open(os.environ["PROVISION_AUDIT_LOG"], "a").write(repr(args))\n')
            f.write('sys.addaudithook(audit)\n')
        env = os.environ.copy()
        env["PYTHONPATH"] = td
        env["PROVISION_AUDIT_LOG"] = audit_log
        run_provision(env)
        assert os.path.isfile(audit_log), "provision.py did not launch a subprocess."
        with open(audit_log, "r") as f:
            audit_data = f.read().lower()
        assert "openssl" in audit_data, "provision.py did not invoke openssl through subprocess."

    metrics1 = read_metrics()
    assert set(metrics1.keys()) == {"vm", "vnc_port", "status"}, "metrics.json must contain exactly the requested keys."
    assert metrics1 == {"vm": name1, "vnc_port": 5900 + display1, "status": "running"}
    assert os.path.isfile(GATEWAY_SCRIPT), f"{GATEWAY_SCRIPT} was not generated."
    assert_certificate_properties()

    display2 = secrets.randbelow(80) + 81
    name2 = "vm-" + secrets.token_hex(8)
    with open(CONFIG_FILE, "w") as f:
        f.write(f"VM_NAME={name2}\nVNC_DISPLAY=:{display2}\nVCPUS=7\n")
    run_provision()

    expected = {"vm": name2, "vnc_port": 5900 + display2, "status": "running"}
    assert read_metrics() == expected, "provision.py did not re-read the changed VM configuration."
    assert fetch_gateway_metrics() == expected, "HTTPS gateway did not serve the dynamically generated metrics."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
