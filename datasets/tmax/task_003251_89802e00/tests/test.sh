#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import hmac
import hashlib
import urllib.request
import urllib.error
import ssl
import pytest


def test_infrastructure_certs_exist():
    assert os.path.isfile("/home/user/certs/tls.crt"), "TLS certificate missing at /home/user/certs/tls.crt"
    assert os.path.isfile("/home/user/certs/tls.key"), "TLS private key missing at /home/user/certs/tls.key"


def test_infrastructure_nginx_conf_exists():
    assert os.path.isfile("/home/user/nginx.conf"), "Nginx config missing at /home/user/nginx.conf"


def test_infrastructure_nginx_proxy():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    req = urllib.request.Request("https://127.0.0.1:8443/log", method="POST")
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            body = response.read().decode("utf-8")
            assert "Log received" in body, f"Expected 'Log received' in response, got {body}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx proxy on port 8443: {e}")


def test_fuzz_equivalence_log_normalizer():
    agent_script = "/home/user/log_normalizer.py"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"

    random.seed(42)
    key = b"COMPLIANCE_KEY_2024"
    lines = []
    expected_lines = []

    for _ in range(1000):
        msg_len = random.randint(10, 200)
        msg = "".join(random.choices(string.ascii_letters + string.digits, k=msg_len))
        expected_mac = hmac.new(key, msg.encode("utf-8"), hashlib.sha256).hexdigest()

        if random.choice([True, False]):
            mac = expected_mac
        else:
            mac = "".join(random.choices("0123456789abcdef", k=64))

        lines.append(f"{mac}:{msg}")
        if hmac.compare_digest(expected_mac, mac):
            expected_lines.append(f"[VERIFIED] {msg}")
        else:
            expected_lines.append(f"[TAMPERED] {msg}")

    input_data = "\n".join(lines) + "\n"
    agent_proc = subprocess.run(
        ["python3", agent_script],
        input=input_data,
        text=True,
        capture_output=True
    )

    assert agent_proc.returncode == 0, f"Agent script failed with error: {agent_proc.stderr}"
    agent_lines = agent_proc.stdout.splitlines()

    assert len(agent_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines of output, got {len(agent_lines)}"

    for i, (expected, actual) in enumerate(zip(expected_lines, agent_lines)):
        if expected != actual:
            pytest.fail(f"Mismatch on line {i + 1}.\nInput: {lines[i]}\nExpected: {expected}\nGot: {actual}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
