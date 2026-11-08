#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import signal
import socket
import ssl
import stat
import subprocess
import time

import pytest


def test_suspicious_port_file():
    port_file = "/home/user/incident_report/suspicious_port.txt"
    assert os.path.isfile(port_file), f"File {port_file} does not exist."
    with open(port_file, "r") as f:
        content = f.read().strip()
    assert content == "8427", f"Expected port 8427 in {port_file}, but found '{content}'."


def test_extracted_certificate():
    cert_file = "/home/user/incident_report/extracted_cert.pem"
    assert os.path.isfile(cert_file), f"Certificate file {cert_file} does not exist."

    with open(cert_file, "r") as f:
        cert_data = f.read()

    assert "-----BEGIN CERTIFICATE-----" in cert_data, "Certificate does not contain BEGIN CERTIFICATE block."
    assert "-----END CERTIFICATE-----" in cert_data, "Certificate does not contain END CERTIFICATE block."

    try:
        submitted_der = ssl.PEM_cert_to_DER_cert(cert_data)
    except ValueError as exc:
        pytest.fail(f"Extracted certificate is not valid PEM: {exc}")

    context = ssl._create_unverified_context()
    with socket.create_connection(("localhost", 8427), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname="localhost") as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)

    assert submitted_der == served_der, "The extracted certificate is not the certificate served on port 8427."


def test_file_permissions():
    expected_modes = {
        "/home/user/incident_data/log_a.dat": 0o600,
        "/home/user/incident_data/log_b.dat": 0o600,
        "/home/user/incident_data/log_c.dat": 0o600,
        "/home/user/incident_data/log_d.dat": 0o640,
    }

    for filepath, expected_mode in expected_modes.items():
        assert os.path.isfile(filepath), f"Data file {filepath} is missing."
        mode = stat.S_IMODE(os.stat(filepath).st_mode)
        assert mode == expected_mode, f"Permissions of {filepath} are incorrect. Expected {oct(expected_mode)}, got {oct(mode)}."


def test_secured_files_list():
    secured_list_file = "/home/user/incident_report/secured_files.txt"
    assert os.path.isfile(secured_list_file), f"File {secured_list_file} does not exist."

    with open(secured_list_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["log_a.dat", "log_c.dat"]
    assert lines == expected_lines, f"Expected {expected_lines} in {secured_list_file}, but found {lines}."


def test_script_modifications():
    script_path = "/home/user/scripts/decrypt_data.py"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    assert "8427" in content, "The script does not contain the updated port 8427."
    assert "verify" in content, "The script does not use the 'verify' parameter in requests.get()."
    assert "/home/user/incident_report/extracted_cert.pem" in content, "The script does not verify against the extracted certificate."
    assert "verify=False" not in content.replace(" ", ""), "The script disabled SSL verification (verify=False), which is disallowed."


def test_decrypted_intel_json():
    json_path = "/home/user/incident_report/decrypted_intel.json"
    assert os.path.isfile(json_path), f"JSON file {json_path} does not exist. Did you run the script successfully?"

    with open(json_path, "r") as f:
        try:
            intel = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    expected_intel = {
        "log_a.dat": "encrypted_payload_alpha_decrypted_with_secret_incident_key_99",
        "log_b.dat": "encrypted_payload_beta_decrypted_with_secret_incident_key_99",
        "log_c.dat": "encrypted_payload_gamma_decrypted_with_secret_incident_key_99",
        "log_d.dat": "encrypted_payload_delta_decrypted_with_secret_incident_key_99"
    }
    assert intel == expected_intel, f"Decrypted intel JSON does not match expected output. Got: {intel}"


def _stop_original_service():
    victims = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [part.decode(errors="ignore") for part in f.read().split(b"\0") if part]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if "/home/user/.server_hidden/server.py" in args and "8427" in args:
            victims.append(int(entry))
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline:
        if all(not os.path.exists(f"/proc/{pid}") for pid in victims):
            return
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def _wait_for_listener(proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail("Temporary HTTPS service exited before accepting connections.")
        try:
            with socket.create_connection(("localhost", 8427), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail("Temporary HTTPS service did not start on port 8427.")


def test_script_really_uses_verified_tls_and_processes_data(tmp_path):
    script_path = "/home/user/scripts/decrypt_data.py"
    cert_path = "/home/user/incident_report/extracted_cert.pem"
    json_path = "/home/user/incident_report/decrypted_intel.json"
    server_cert = "/home/user/.server_hidden/cert.pem"
    server_key = "/home/user/.server_hidden/key.pem"

    cert_backup = open(cert_path, "rb").read()
    cert_mode = stat.S_IMODE(os.stat(cert_path).st_mode)
    output_backup = open(json_path, "rb").read()
    output_mode = stat.S_IMODE(os.stat(json_path).st_mode)

    probe_name = f"probe_{secrets.token_hex(8)}.dat"
    probe_path = os.path.join("/home/user/incident_data", probe_name)
    probe_content = f"verifier_payload_{secrets.token_hex(12)}"
    dynamic_key = f"verifier_key_{secrets.token_hex(16)}"
    request_log = str(tmp_path / "requests.log")
    temp_server_source = str(tmp_path / "https_server.py")
    wrong_key = str(tmp_path / "wrong.key")
    wrong_cert = str(tmp_path / "wrong.pem")

    with open(probe_path, "w") as f:
        f.write(probe_content + "\n")
    os.chmod(probe_path, 0o600)

    server_program = r'''import http.server
import json
import ssl
import sys

cert, keyfile, value, log_path = sys.argv[1:]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(log_path, "a") as log:
            log.write(self.path + "\n")
        if self.path == "/key.json":
            body = json.dumps({"key": value}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *args):
        pass

httpd = http.server.HTTPServer(("localhost", 8427), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile=cert, keyfile=keyfile)
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
'''
    with open(temp_server_source, "w") as f:
        f.write(server_program)

    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-days", "1", "-subj", "/CN=localhost",
        "-keyout", wrong_key, "-out", wrong_cert
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    temp_server = None
    try:
        _stop_original_service()
        temp_server = subprocess.Popen(
            ["python3", temp_server_source, server_cert, server_key, dynamic_key, request_log],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        _wait_for_listener(temp_server)

        # With an unrelated CA file, a securely verified request must fail and
        # therefore must not produce a successful output file.
        with open(wrong_cert, "rb") as src, open(cert_path, "wb") as dst:
            dst.write(src.read())
        if os.path.exists(json_path):
            os.unlink(json_path)
        subprocess.run(["python3", script_path], timeout=15, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert not os.path.exists(json_path), "The script succeeded with an unrelated certificate; TLS verification was bypassed or ignored."

        # Restore the actual service certificate and require the submitted
        # script to fetch an unpredictable key and process an unpredictable file.
        with open(cert_path, "wb") as f:
            f.write(cert_backup)
        os.chmod(cert_path, cert_mode)
        subprocess.run(["python3", script_path], check=False, timeout=15, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert os.path.isfile(json_path), "Running the updated script did not create decrypted_intel.json."

        with open(request_log, "r") as f:
            requested_paths = [line.strip() for line in f if line.strip()]
        assert "/key.json" in requested_paths, "The script did not request /key.json from the HTTPS service."

        expected = {}
        for filepath in sorted(glob.glob("/home/user/incident_data/*.dat")):
            with open(filepath, "r") as f:
                content = f.read().strip()
            expected[os.path.basename(filepath)] = f"{content}_decrypted_with_{dynamic_key}"
        with open(json_path, "r") as f:
            actual = json.load(f)
        assert actual == expected, f"Executed script did not produce dynamically derived results. Got: {actual}"
    finally:
        if temp_server is not None and temp_server.poll() is None:
            temp_server.terminate()
            try:
                temp_server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                temp_server.kill()
                temp_server.wait(timeout=5)
        if os.path.exists(probe_path):
            os.unlink(probe_path)
        with open(cert_path, "wb") as f:
            f.write(cert_backup)
        os.chmod(cert_path, cert_mode)
        with open(json_path, "wb") as f:
            f.write(output_backup)
        os.chmod(json_path, output_mode)
        original = subprocess.Popen(
            ["python3", "/home/user/.server_hidden/server.py", "8427"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        with open("/home/user/.server_hidden/server.pid", "w") as f:
            f.write(str(original.pid) + "\n")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
