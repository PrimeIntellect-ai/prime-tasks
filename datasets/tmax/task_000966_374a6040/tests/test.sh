#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import socket
import ssl
import subprocess
import time
import urllib.error
import urllib.request

import pytest

CERT_PATH = "/home/user/certs/cert.pem"
KEY_PATH = "/home/user/certs/key.pem"
SCRIPT_PATH = "/home/user/secure_api.py"
MANAGER_PATH = "/home/user/manage_services.sh"
PID_PATH = "/home/user/api.pid"
METRICS_PATH = "/home/user/parsed_metrics.json"
EXPECTED = {
    "auth-service": 125,
    "billing-service": 307,
    "inventory-service": 47,
}


def unverified_context():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def fetch(path):
    req = urllib.request.Request("https://localhost:9443" + path)
    return urllib.request.urlopen(req, context=unverified_context(), timeout=5)


def process_state(pid):
    try:
        with open(f"/proc/{pid}/status", "r") as f:
            for line in f:
                if line.startswith("State:"):
                    return line.split()[1]
    except (FileNotFoundError, ProcessLookupError):
        return None
    return None


def process_start_time(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            stat = f.read()
        return stat[stat.rfind(")") + 2:].split()[19]
    except (FileNotFoundError, ProcessLookupError, IndexError):
        return None


def pid_owns_9443_listener(pid):
    socket_inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith("socket:[") and target.endswith("]"):
                socket_inodes.add(target[8:-1])
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return False

    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local_address = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    try:
                        port = int(local_address.rsplit(":", 1)[1], 16)
                    except (ValueError, IndexError):
                        continue
                    if port == 9443 and state == "0A" and inode in socket_inodes:
                        return True
        except FileNotFoundError:
            pass
    return False


def assert_pid_is_secure_api_server(pid):
    assert process_state(pid) not in (None, "Z"), f"Process with PID {pid} is not running."

    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    assert len(argv) >= 2, f"PID {pid} has an unexpected command line: {argv}"

    exe = os.path.realpath(f"/proc/{pid}/exe")
    assert os.path.basename(exe).startswith("python"), f"PID {pid} is not a Python process: {exe}"
    assert os.path.realpath(argv[1]) == SCRIPT_PATH, \
        f"PID {pid} is not executing {SCRIPT_PATH}: {argv}"
    assert pid_owns_9443_listener(pid), \
        f"PID {pid} does not own the listening socket on port 9443."


def wait_for_pid_server(pid, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            assert_pid_is_secure_api_server(pid)
            with fetch("/metrics") as response:
                if response.status == 200:
                    return
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    pytest.fail(f"PID {pid} did not become the HTTPS server: {last_error}")


def read_pid():
    assert os.path.isfile(PID_PATH), f"PID file {PID_PATH} does not exist after running script."
    with open(PID_PATH, "r") as f:
        value = f.read().strip()
    assert value.isdigit(), f"PID file does not contain a valid PID: {value}"
    return int(value), value


def peer_certificate_der():
    with socket.create_connection(("localhost", 9443), timeout=5) as raw:
        with unverified_context().wrap_socket(raw, server_hostname="localhost") as tls_sock:
            return tls_sock.getpeercert(binary_form=True)


def test_parsed_metrics_json():
    """Verify parsed_metrics.json exists and contains correct averages."""
    assert os.path.isfile(METRICS_PATH), f"File {METRICS_PATH} does not exist."
    with open(METRICS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {METRICS_PATH} is not valid JSON.")
    assert data == EXPECTED, f"Content of {METRICS_PATH} does not match expected metrics."


def test_tls_certs_exist_and_are_valid():
    """Verify the certificate and key meet the requested TLS properties."""
    assert os.path.isfile(CERT_PATH), f"Certificate file {CERT_PATH} does not exist."
    assert os.path.isfile(KEY_PATH), f"Key file {KEY_PATH} does not exist."

    with open(KEY_PATH, "rb") as f:
        key_contents = f.read()
    assert b"ENCRYPTED" not in key_contents, "The private key is encrypted."

    subprocess.run(
        ["openssl", "pkey", "-in", KEY_PATH, "-noout", "-check"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5, check=True,
    )
    key_text = subprocess.run(
        ["openssl", "rsa", "-in", KEY_PATH, "-text", "-noout"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5, check=True,
    ).stdout.decode(errors="replace")
    assert "Private-Key: (2048 bit" in key_text, "The private key is not RSA-2048."

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", CERT_PATH, "-pubkey", "-noout"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    ).stdout
    cert_pub_der = subprocess.run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    ).stdout
    key_pub_der = subprocess.run(
        ["openssl", "pkey", "-in", KEY_PATH, "-pubout", "-outform", "DER"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5, check=True,
    ).stdout
    assert cert_pub_der == key_pub_der, "cert.pem and key.pem do not form a matching pair."

    subprocess.run(
        ["openssl", "verify", "-CAfile", CERT_PATH, CERT_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    )
    dates = subprocess.run(
        ["openssl", "x509", "-in", CERT_PATH, "-noout", "-startdate", "-enddate"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    ).stdout.decode().strip().splitlines()
    date_values = dict(line.split("=", 1) for line in dates)
    date_format = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(date_values["notBefore"], date_format)
    not_after = datetime.datetime.strptime(date_values["notAfter"], date_format)
    assert not_after - not_before == datetime.timedelta(days=365), \
        "Certificate validity period is not exactly 365 days."
    now = datetime.datetime.utcnow()
    assert not_before <= now <= not_after, "Certificate is not currently valid."


def test_secure_api_script_exists():
    """Verify secure_api.py exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_manage_services_script_exists_and_executable():
    """Verify manage_services.sh exists and is executable."""
    assert os.path.isfile(MANAGER_PATH), f"Script {MANAGER_PATH} does not exist."
    assert os.access(MANAGER_PATH, os.X_OK), f"Script {MANAGER_PATH} is not executable."


def test_https_server_response():
    """Verify the HTTPS server serves the metrics and handles 404 properly."""
    try:
        with fetch("/metrics") as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            content_type = response.headers.get("Content-Type", "")
            assert "application/json" in content_type, \
                f"Expected Content-Type application/json, got {content_type}"
            data = json.loads(response.read().decode("utf-8"))
            assert data == EXPECTED, "API response does not match expected metrics."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to https://localhost:9443/metrics: {e}")

    try:
        fetch("/invalid_path")
        pytest.fail("Expected 404 Not Found for invalid path, but request succeeded.")
    except urllib.error.HTTPError as e:
        assert e.code == 404, f"Expected status 404 for invalid path, got {e.code}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to https://localhost:9443/invalid_path: {e}")


def test_manage_services_idempotency():
    """Verify restart lifecycle, PID ownership, script identity, TLS files, and live file reads."""
    subprocess.run([MANAGER_PATH], check=True)
    pid1, pid1_text = read_pid()
    wait_for_pid_server(pid1)
    old_start_time = process_start_time(pid1)

    subprocess.run([MANAGER_PATH], check=True)
    pid2, pid2_text = read_pid()
    assert pid1_text != pid2_text, \
        "PID did not change after running manage_services.sh, service was not restarted."
    wait_for_pid_server(pid2)

    deadline = time.time() + 5
    while time.time() < deadline:
        state = process_state(pid1)
        same_process = process_start_time(pid1) == old_start_time
        if state in (None, "Z") or not same_process:
            break
        time.sleep(0.1)
    else:
        pytest.fail(f"Old server process with PID {pid1} was not terminated.")

    try:
        os.kill(pid2, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid2} is not running.")
    assert_pid_is_secure_api_server(pid2)

    with open(CERT_PATH, "r") as f:
        expected_peer_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert peer_certificate_der() == expected_peer_der, \
        "The server on port 9443 is not using /home/user/certs/cert.pem."

    with open(METRICS_PATH, "rb") as f:
        original_metrics = f.read()
    probe = {"verifier-dynamic-service": 731}
    try:
        with open(METRICS_PATH, "w") as f:
            json.dump(probe, f)
        with fetch("/metrics") as response:
            assert response.status == 200
            assert "application/json" in response.headers.get("Content-Type", "")
            assert json.loads(response.read().decode("utf-8")) == probe, \
                "The deployed secure_api.py did not read parsed_metrics.json for the request."
    finally:
        with open(METRICS_PATH, "wb") as f:
            f.write(original_metrics)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
