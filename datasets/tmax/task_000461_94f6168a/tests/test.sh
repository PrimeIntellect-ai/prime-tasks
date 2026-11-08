#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncore
import hashlib
import os
import smtplib
import smtpd
import ssl
import stat
import subprocess
import threading
import time
import urllib.request
import uuid

DEPLOY = "/home/user/deploy_edge.py"
SENSOR = "/home/user/bin/mock_sensor"
COLLECTOR = "/home/user/bin/collect.py"
METRICS = "/home/user/webroot/metrics.html"
CERT = "/home/user/certs/cert.pem"
KEY = "/home/user/certs/key.pem"
CRON_MARKER = "17 3 * * * /bin/true # verifier-preserve"


def get_crontab():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    if result.returncode != 0:
        return ""
    return result.stdout


def install_preservation_marker():
    current = get_crontab()
    lines = current.splitlines()
    if CRON_MARKER not in lines:
        lines.append(CRON_MARKER)
        new_crontab = "\n".join(lines) + "\n"
        result = subprocess.run(["crontab", "-"], input=new_crontab, text=True, capture_output=True)
        assert result.returncode == 0, f"Could not install test cron marker: {result.stderr}"


def managed_state():
    paths = [
        SENSOR,
        COLLECTOR,
        "/home/user/bin/start_web.sh",
        CERT,
        KEY,
    ]
    state = {}
    for path in paths:
        assert os.path.isfile(path), f"Expected managed file missing: {path}"
        with open(path, "rb") as f:
            data = f.read()
        state[path] = (hashlib.sha256(data).hexdigest(), stat.S_IMODE(os.stat(path).st_mode))
    state["crontab"] = get_crontab()
    return state


def test_deploy_script_exists():
    assert os.path.isfile(DEPLOY), "deploy_edge.py not found"


def test_run_deploy_script():
    install_preservation_marker()

    result = subprocess.run(["/usr/bin/python3", DEPLOY], capture_output=True, text=True)
    assert result.returncode == 0, f"deploy_edge.py failed: {result.stderr}"
    assert CRON_MARKER in get_crontab().splitlines(), "Deployment deleted an unrelated cron entry"
    first_state = managed_state()

    # Run again and require the resulting managed state to remain unchanged.
    result2 = subprocess.run(["/usr/bin/python3", DEPLOY], capture_output=True, text=True)
    assert result2.returncode == 0, f"deploy_edge.py failed on second run: {result2.stderr}"
    assert managed_state() == first_state, "Deployment changed files, modes, or crontab on its second run"


def test_directories_created():
    for d in ["/home/user/webroot", "/home/user/certs", "/home/user/bin"]:
        assert os.path.isdir(d), f"Directory {d} was not created"


def test_mock_sensor():
    assert os.path.isfile(SENSOR), "mock_sensor not found"
    assert os.access(SENSOR, os.X_OK), "mock_sensor is not executable"
    result = subprocess.run([SENSOR], capture_output=True, text=True)
    assert "TEMP=42.5C LOAD=1.2" in result.stdout, "mock_sensor output is incorrect"


def test_certificates():
    assert os.path.isfile(CERT), "cert.pem not found"
    assert os.path.isfile(KEY), "key.pem not found"

    cert_info = subprocess.run(
        ["openssl", "x509", "-in", CERT, "-noout", "-subject", "-issuer"],
        capture_output=True,
        text=True,
    )
    assert cert_info.returncode == 0, f"cert.pem is not a valid X.509 certificate: {cert_info.stderr}"
    info_lines = [line.strip() for line in cert_info.stdout.splitlines() if line.strip()]
    assert len(info_lines) == 2, "Could not read certificate subject and issuer"
    subject = info_lines[0].split("=", 1)[1].strip()
    issuer = info_lines[1].split("=", 1)[1].strip()
    assert subject == issuer, "Certificate is not self-signed"

    verified = subprocess.run(
        ["openssl", "verify", "-CAfile", CERT, CERT], capture_output=True, text=True
    )
    assert verified.returncode == 0, f"Self-signed certificate verification failed: {verified.stderr}"

    rsa_check = subprocess.run(
        ["openssl", "rsa", "-in", KEY, "-check", "-noout"], capture_output=True, text=True
    )
    assert rsa_check.returncode == 0, f"key.pem is not a valid RSA private key: {rsa_check.stderr}"

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", CERT, "-pubkey", "-noout"], capture_output=True
    )
    assert cert_pub.returncode == 0, "Could not extract certificate public key"
    pub_info = subprocess.run(
        ["openssl", "pkey", "-pubin", "-text", "-noout"],
        input=cert_pub.stdout,
        capture_output=True,
    )
    assert pub_info.returncode == 0, "Certificate does not contain a valid public key"
    assert b"2048 bit" in pub_info.stdout, "Certificate public key is not 2048 bits"

    cert_pub_der = subprocess.run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"],
        input=cert_pub.stdout,
        capture_output=True,
    )
    key_pub_der = subprocess.run(
        ["openssl", "pkey", "-in", KEY, "-pubout", "-outform", "DER"],
        capture_output=True,
    )
    assert cert_pub_der.returncode == 0 and key_pub_der.returncode == 0, "Could not compare certificate and key"
    assert cert_pub_der.stdout == key_pub_der.stdout, "Certificate and private key do not match"


def test_crontab():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    lines = result.stdout.strip().split("\n")
    cron_entries = [
        line for line in lines
        if "/usr/bin/python3 /home/user/bin/collect.py" in line
        and not line.strip().startswith("#")
    ]
    assert len(cron_entries) == 1, "Expected exactly one cron entry for collect.py"
    assert cron_entries[0].startswith("* * * * *"), "Cron entry does not run every minute"
    assert CRON_MARKER in lines, "Unrelated cron entry was not preserved"


def test_collector_execution():
    assert os.path.isfile(COLLECTOR), "collect.py not found"

    class DummySMTPServer(smtpd.SMTPServer):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self.emails = []

        def process_message(self, peer, mailfrom, rcpttos, data, **kwargs):
            self.emails.append((mailfrom, rcpttos, data))

    smtp_server = DummySMTPServer(("127.0.0.1", 8025), None)
    thread = threading.Thread(target=asyncore.loop, kwargs={"timeout": 0.1, "use_poll": True})
    thread.daemon = True
    thread.start()

    with open(SENSOR, "rb") as f:
        original_sensor = f.read()
    original_mode = stat.S_IMODE(os.stat(SENSOR).st_mode)
    dynamic_value = "TEMP=DYNAMIC-" + uuid.uuid4().hex + "C LOAD=9.7"

    try:
        # Replace the sensor output with an unpredictable value to prove that
        # collect.py actually executes the absolute sensor path.
        with open(SENSOR, "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\n' '" + dynamic_value + "'\n")
        os.chmod(SENSOR, 0o755)

        result = subprocess.run(
            ["env", "-i", "/usr/bin/python3", COLLECTOR],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"collect.py failed with empty env: {result.stderr}"
        assert os.path.isfile(METRICS), "metrics.html not found"
        with open(METRICS, "r") as f:
            dynamic_content = f.read()
        assert dynamic_content == f"<h1>{dynamic_value}</h1>", "Collector did not use the current mock_sensor output exactly"

        # Restore the required sensor and exercise the specified fixed output too.
        with open(SENSOR, "wb") as f:
            f.write(original_sensor)
        os.chmod(SENSOR, original_mode)
        result2 = subprocess.run(
            ["env", "-i", "/usr/bin/python3", COLLECTOR],
            capture_output=True,
            text=True,
        )
        assert result2.returncode == 0, f"collect.py failed after sensor restoration: {result2.stderr}"
        with open(METRICS, "r") as f:
            content = f.read()
        assert "<h1>TEMP=42.5C LOAD=1.2</h1>" in content, "metrics.html content is incorrect"

        deadline = time.time() + 2
        while len(smtp_server.emails) < 2 and time.time() < deadline:
            time.sleep(0.05)
        assert len(smtp_server.emails) > 0, "No email was sent"
        mailfrom, rcpttos, data = smtp_server.emails[-1]
        assert "device@edge.local" in mailfrom, "Incorrect sender"
        assert "admin@edge.local" in rcpttos, "Incorrect recipient"
        data_str = data.decode("utf-8", errors="ignore")
        assert "Subject: Alert" in data_str, "Incorrect subject"
        assert "Metrics updated" in data_str, "Incorrect body"
    finally:
        with open(SENSOR, "wb") as f:
            f.write(original_sensor)
        os.chmod(SENSOR, original_mode)
        smtp_server.close()


def test_web_server():
    web_script = "/home/user/bin/start_web.sh"
    assert os.path.isfile(web_script), "start_web.sh not found"
    assert os.access(web_script, os.X_OK), "start_web.sh is not executable"

    proc = subprocess.Popen([web_script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)

    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        req = urllib.request.Request("https://127.0.0.1:8443/metrics.html")
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.status == 200, "Web server did not return 200 OK"
            content = response.read().decode("utf-8")
            assert "<h1>TEMP=42.5C LOAD=1.2</h1>" in content, "Web server returned incorrect content"
    finally:
        proc.terminate()
        proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
