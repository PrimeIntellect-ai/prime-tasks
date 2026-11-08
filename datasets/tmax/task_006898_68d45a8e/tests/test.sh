#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import ssl
import subprocess
import time
import pytest

API_DIR = "/home/user/vnc-api"
BINARY = f"{API_DIR}/vnc-manager"
LOG = f"{API_DIR}/api.log"
CERT = f"{API_DIR}/certs/server.crt"
KEY = f"{API_DIR}/certs/server.key"
EXPECTED_RAW = b'{"service": "vnc-manager", "status": "running", "active_vms": 0}'


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, **kwargs)


def listener_pids():
    proc = run(["lsof", "-nP", "-t", "-iTCP:8443", "-sTCP:LISTEN"], text=True)
    if proc.returncode not in (0, 1):
        pytest.fail(f"lsof failed: {proc.stderr}")
    return [int(line) for line in proc.stdout.splitlines() if line.strip().isdigit()]


def curl_status():
    return run([
        "curl", "-skS", "--max-time", "5",
        "https://127.0.0.1:8443/status"
    ])


def assert_service_is_binary():
    pids = listener_pids()
    assert pids, "Nothing is listening on TCP port 8443"
    matching = []
    for pid in pids:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", BINARY):
                matching.append(pid)
        except (FileNotFoundError, PermissionError, OSError):
            pass
    assert matching, f"Port 8443 is not owned by the compiled {BINARY} process"

    response = curl_status()
    assert response.returncode == 0, response.stderr.decode(errors="replace")
    assert response.stdout == EXPECTED_RAW, "The live HTTPS /status response is incorrect"

    served_pem = ssl.get_server_certificate(("127.0.0.1", 8443))
    with open(CERT, "r") as f:
        local_pem = f.read()
    assert ssl.PEM_cert_to_DER_cert(served_pem) == ssl.PEM_cert_to_DER_cert(local_pem), \
        "The HTTPS service is not serving certs/server.crt"
    return matching


def test_go_code_fixed():
    main_go_path = "/home/user/vnc-api/main.go"
    assert os.path.isfile(main_go_path), f"{main_go_path} is missing"

    with open(main_go_path, 'r') as f:
        content = f.read()

    assert "/home/user/vnc-api/certs/server.crt" in content, "main.go does not contain the correct path for server.crt"
    assert "/home/user/vnc-api/certs/server.key" in content, "main.go does not contain the correct path for server.key"
    assert "/etc/ssl/certs/server.crt" not in content, "main.go still contains the hardcoded incorrect cert path"


def test_certs_exist():
    cert_path = CERT
    key_path = KEY

    assert os.path.isfile(cert_path), f"Certificate file {cert_path} is missing"
    assert os.path.isfile(key_path), f"Key file {key_path} is missing"
    assert os.path.getsize(cert_path) > 0, f"Certificate file {cert_path} is empty"
    assert os.path.getsize(key_path) > 0, f"Key file {key_path} is empty"

    cert_check = run(["openssl", "x509", "-in", cert_path, "-noout", "-checkend", "0"], text=True)
    assert cert_check.returncode == 0, f"Invalid or expired TLS certificate: {cert_check.stderr}"

    key_check = run(["openssl", "rsa", "-in", key_path, "-noout", "-check"], text=True)
    assert key_check.returncode == 0, f"Invalid RSA private key: {key_check.stderr}"

    key_text = run(["openssl", "rsa", "-in", key_path, "-noout", "-text"], text=True)
    assert key_text.returncode == 0
    assert "Private-Key: (2048 bit" in key_text.stdout, "Private key is not RSA 2048-bit"

    cert_text = run(["openssl", "x509", "-in", cert_path, "-noout", "-text"], text=True)
    assert cert_text.returncode == 0
    assert "Public Key Algorithm: rsaEncryption" in cert_text.stdout, "Certificate does not contain an RSA key"
    assert "Public-Key: (2048 bit)" in cert_text.stdout, "Certificate RSA key is not 2048-bit"

    cert_mod = run(["openssl", "x509", "-in", cert_path, "-noout", "-modulus"], text=True)
    key_mod = run(["openssl", "rsa", "-in", key_path, "-noout", "-modulus"], text=True)
    assert cert_mod.returncode == 0 and key_mod.returncode == 0
    assert cert_mod.stdout.strip() == key_mod.stdout.strip(), "Certificate and private key do not match"

    verify = run(["openssl", "verify", "-CAfile", cert_path, cert_path], text=True)
    assert verify.returncode == 0, f"Certificate is not valid as a self-signed certificate: {verify.stderr}"


def test_deploy_script_exists_and_executable():
    script_path = "/home/user/deploy.sh"
    assert os.path.isfile(script_path), f"Deploy script {script_path} is missing"
    assert os.access(script_path, os.X_OK), f"Deploy script {script_path} is not executable"


def test_vnc_manager_compiled_and_logged():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing"
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable"
    assert os.path.isfile(LOG), f"Log file {LOG} is missing"


def test_result_json():
    result_path = "/home/user/result.json"
    assert os.path.isfile(result_path), f"Result file {result_path} is missing"

    with open(result_path, 'r') as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"{result_path} does not contain valid JSON")

    expected_data = {"service": "vnc-manager", "status": "running", "active_vms": 0}
    assert data == expected_data, f"Content of {result_path} does not match the expected API output"


def test_live_service_and_exact_saved_result():
    assert_service_is_binary()
    with open("/home/user/result.json", "rb") as f:
        saved = f.read()
    assert saved == EXPECTED_RAW, "result.json is not the exact raw response from the API"


def test_z_deploy_script_rebuilds_and_launches_service():
    # Stop the verified existing instance, remove its products, and exercise deploy.sh itself.
    old_pids = listener_pids()
    for pid in old_pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while listener_pids() and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    time.sleep(0.2)
    assert not listener_pids(), "Port 8443 could not be cleared before testing deploy.sh"

    for path in (BINARY, LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        deployed = run(["/home/user/deploy.sh"], cwd="/home/user", text=True, timeout=60)
    except subprocess.TimeoutExpired:
        pytest.fail("deploy.sh did not return after starting the service in the background")
    assert deployed.returncode == 0, f"deploy.sh failed:\nstdout: {deployed.stdout}\nstderr: {deployed.stderr}"

    assert os.path.isfile(BINARY), "deploy.sh did not compile vnc-manager"
    assert os.access(BINARY, os.X_OK), "deploy.sh did not create an executable vnc-manager"
    go_info = run(["go", "version", "-m", BINARY], text=True)
    assert go_info.returncode == 0 and "go1" in go_info.stdout, "vnc-manager is not a compiled Go binary"

    deadline = time.time() + 15
    pids = []
    while time.time() < deadline:
        try:
            pids = assert_service_is_binary()
            break
        except AssertionError:
            time.sleep(0.25)
    else:
        pytest.fail("deploy.sh did not launch a working HTTPS vnc-manager service on port 8443")

    assert os.path.isfile(LOG), "deploy.sh did not create api.log"
    for pid in pids:
        try:
            assert os.path.samefile(f"/proc/{pid}/fd/1", LOG), "Service stdout is not redirected to api.log"
            assert os.path.samefile(f"/proc/{pid}/fd/2", LOG), "Service stderr is not redirected to api.log"
        except FileNotFoundError:
            pytest.fail("The deployed service exited unexpectedly")

    response = curl_status()
    assert response.returncode == 0
    with open("/home/user/result.json", "rb") as f:
        assert f.read() == response.stdout, "result.json does not exactly match the live API output"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
