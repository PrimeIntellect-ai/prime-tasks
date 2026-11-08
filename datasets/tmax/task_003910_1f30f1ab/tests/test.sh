#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import pathlib
import pwd
import subprocess
import time
import uuid

import pytest


def run(command, check=True):
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)


def systemctl(*args, check=True):
    account = pwd.getpwnam("user")
    runtime_dir = f"/run/user/{account.pw_uid}"
    command = [
        "/usr/sbin/runuser", "-u", "user", "--",
        "/usr/bin/env",
        f"XDG_RUNTIME_DIR={runtime_dir}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime_dir}/bus",
        "/usr/bin/systemctl", "--user", *args,
    ]
    return run(command, check=check)


def unit_properties(unit, *properties):
    result = systemctl("show", unit, *(f"--property={p}" for p in properties))
    values = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def wait_for_file(path, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            return
        time.sleep(0.1)
    pytest.fail(f"Timed out waiting for '{path}' to be written")


def test_executable_compiled():
    """Check that the C++ API server has been compiled and is executable."""
    executable_path = "/home/user/cost_api"
    assert os.path.isfile(executable_path), f"Executable '{executable_path}' does not exist. Did you compile the C++ code?"
    assert os.access(executable_path, os.X_OK), f"File '{executable_path}' is not executable."
    with open(executable_path, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "The API executable is not a compiled ELF program."
    dependencies = run(["/usr/bin/ldd", executable_path]).stdout
    assert "libssl.so" in dependencies, "The API executable is not linked to OpenSSL libssl."
    assert "libcrypto.so" in dependencies, "The API executable is not linked to OpenSSL libcrypto."


def test_tls_certificates_exist():
    """Check that the TLS certificates have been generated."""
    key_path = "/home/user/key.pem"
    cert_path = "/home/user/cert.pem"
    assert os.path.isfile(key_path), f"Private key '{key_path}' does not exist."
    assert os.path.isfile(cert_path), f"Certificate '{cert_path}' does not exist."

    key_text = run(["/usr/bin/openssl", "pkey", "-in", key_path, "-text", "-noout"]).stdout
    assert "Private-Key: (2048 bit" in key_text, "The private key is not a valid 2048-bit key."
    cert_text = run(["/usr/bin/openssl", "x509", "-in", cert_path, "-text", "-noout"]).stdout
    assert "Public-Key: (2048 bit)" in cert_text, "The certificate does not contain a 2048-bit RSA public key."

    subject = run(["/usr/bin/openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"]).stdout.strip()
    issuer = run(["/usr/bin/openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253"]).stdout.strip()
    assert subject == "subject=CN=localhost", f"Unexpected certificate subject: {subject}"
    assert issuer.replace("issuer=", "", 1) == subject.replace("subject=", "", 1), "The certificate is not self-signed."
    run(["/usr/bin/openssl", "verify", "-CAfile", cert_path, cert_path])

    key_pub = run(["/usr/bin/openssl", "pkey", "-in", key_path, "-pubout"]).stdout
    cert_pub = run(["/usr/bin/openssl", "x509", "-in", cert_path, "-pubkey", "-noout"]).stdout
    assert key_pub == cert_pub, "The private key does not match the certificate."

    dates = run(["/usr/bin/openssl", "x509", "-in", cert_path, "-noout", "-startdate", "-enddate"]).stdout.splitlines()
    not_before = datetime.datetime.strptime(dates[0].split("=", 1)[1], "%b %d %H:%M:%S %Y %Z").replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(dates[1].split("=", 1)[1], "%b %d %H:%M:%S %Y %Z").replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "The certificate is not currently valid."
    validity = not_after - not_before
    assert datetime.timedelta(days=29, hours=23) <= validity <= datetime.timedelta(days=30, hours=1), "The certificate was not issued for 30 days."


def test_api_service_file():
    """Check that the API systemd service file is created correctly."""
    service_path = "/home/user/.config/systemd/user/cost-api.service"
    assert os.path.isfile(service_path), f"Service file '{service_path}' does not exist."
    with open(service_path, "r") as f:
        content = f.read()
    assert "/home/user/cost_api" in content, "The API service does not execute '/home/user/cost_api'."
    assert "Restart=always" in content or "Restart= always" in content, "The API service is not configured to restart always."
    assert "WorkingDirectory=/home/user" in content, "The API service does not set WorkingDirectory=/home/user."


def test_reporter_service_file():
    """Check that the reporter systemd service file is configured correctly."""
    service_path = "/home/user/.config/systemd/user/cost-reporter.service"
    assert os.path.isfile(service_path), f"Service file '{service_path}' does not exist."
    with open(service_path, "r") as f:
        content = f.read()
    assert "Type=oneshot" in content, "The reporter service is not configured as Type=oneshot."
    assert "/home/user/reporter.sh" in content, "The reporter service does not execute '/home/user/reporter.sh'."
    assert "After=cost-api.service" in content, "The reporter service does not contain 'After=cost-api.service'."
    assert "Requires=cost-api.service" in content or "Wants=cost-api.service" in content, "The reporter service does not Require or Want 'cost-api.service'."


def test_systemd_loaded_and_agent_started_units():
    """Validate the parsed units and confirm the requested user services actually ran."""
    api = unit_properties("cost-api.service", "LoadState", "FragmentPath", "ActiveState", "MainPID", "ExecStart", "Restart", "WorkingDirectory")
    assert api["LoadState"] == "loaded"
    assert os.path.realpath(api["FragmentPath"]) == "/home/user/.config/systemd/user/cost-api.service"
    assert api["ActiveState"] == "active", "cost-api.service was not started successfully by the agent."
    assert api["Restart"] == "always"
    assert api["WorkingDirectory"] == "/home/user"
    assert "/home/user/cost_api" in api["ExecStart"]
    pid = int(api["MainPID"])
    assert pid > 0
    assert os.path.realpath(f"/proc/{pid}/exe") == "/home/user/cost_api", "The active API unit is not running the submitted executable."

    reporter = unit_properties("cost-reporter.service", "LoadState", "FragmentPath", "Type", "ExecStart", "After", "Requires", "Result", "ExecMainStatus", "ExecMainStartTimestampMonotonic")
    assert reporter["LoadState"] == "loaded"
    assert os.path.realpath(reporter["FragmentPath"]) == "/home/user/.config/systemd/user/cost-reporter.service"
    assert reporter["Type"] == "oneshot"
    assert "/home/user/reporter.sh" in reporter["ExecStart"]
    assert "cost-api.service" in reporter["After"].split()
    assert "cost-api.service" in reporter["Requires"].split(), "The parsed reporter unit does not require cost-api.service."
    assert reporter["Result"] == "success" and reporter["ExecMainStatus"] == "0", "cost-reporter.service did not complete successfully."
    assert int(reporter["ExecMainStartTimestampMonotonic"]) > 0, "cost-reporter.service was never run."


def test_services_reproduce_report_via_systemd():
    """Start the reporter through systemd and require it to bring up and use the API unit."""
    systemctl("stop", "cost-api.service")
    try:
        os.remove("/home/user/metrics.log")
    except FileNotFoundError:
        pass
    systemctl("start", "cost-reporter.service")
    assert systemctl("is-active", "cost-api.service", check=False).stdout.strip() == "active"
    wait_for_file("/home/user/metrics.log")

    api = unit_properties("cost-api.service", "MainPID", "ActiveState")
    assert api["ActiveState"] == "active"
    pid = int(api["MainPID"])
    assert pid > 0 and os.path.realpath(f"/proc/{pid}/exe") == "/home/user/cost_api"


def test_metrics_log_created_and_valid():
    """Check that the metrics.log was successfully created and contains the expected JSON."""
    log_path = "/home/user/metrics.log"
    assert os.path.isfile(log_path), f"Log file '{log_path}' does not exist. The service might not have started or the reporter failed."

    with open(log_path, "r") as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"Content of '{log_path}' is not valid JSON: {content}")

    expected_data = {"instance": "i-0abcd1234", "spot_price": 0.045, "region": "us-east-1"}
    assert data == expected_data, f"Log file content does not match expected payload. Found: {data}"


def test_live_tls_api_accepts_unpredictable_payload():
    """Exercise the compiled TLS server with verifier-generated data."""
    payload = {
        "instance": "verify-" + uuid.uuid4().hex,
        "spot_price": int.from_bytes(os.urandom(4), "big") / 1000000.0,
        "region": "test-" + uuid.uuid4().hex[:10],
    }
    encoded = json.dumps(payload, separators=(",", ":"))
    response = run([
        "/usr/bin/curl", "--silent", "--show-error", "--fail", "--insecure",
        "--request", "POST", "--data-binary", encoded,
        "https://127.0.0.1:8443/report",
    ])
    assert response.stdout == "Success"
    wait_for_file("/home/user/metrics.log")
    with open("/home/user/metrics.log", "r") as log_file:
        assert json.load(log_file) == payload, "The running API did not write the verifier-generated request body."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
