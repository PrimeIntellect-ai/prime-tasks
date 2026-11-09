#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SERVER_EOF' > /tmp/dynamic_https_server.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import ssl
import sys

host = "127.0.0.1"
port = int(sys.argv[1])
cert = sys.argv[2]
key = sys.argv[3]
payload_path = sys.argv[4]
token = sys.argv[5]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/update.bin":
            self.send_error(404)
            return
        with open(payload_path, "rb") as f:
            body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Set-Cookie", f"X-Incident-Token={token}; Path=/; Secure; HttpOnly")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

httpd = HTTPServer((host, port), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile=cert, keyfile=key)
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
SERVER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import socket
import subprocess
import time

import pytest

SCRIPT_PATH = "/home/user/analyze_endpoint.sh"
REPORT_PATH = "/home/user/investigation_report.txt"


def run_script(host, port, ca, manifest):
    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)
    return subprocess.run(
        [SCRIPT_PATH, host, str(port), str(ca), str(manifest)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def read_strict_report():
    assert os.path.isfile(REPORT_PATH), "Script did not create investigation_report.txt"
    with open(REPORT_PATH, "r") as f:
        content = f.read()
    lines = content.splitlines()
    assert len(lines) == 3, f"Report must contain exactly three lines, got: {content!r}"
    cert = re.fullmatch(r"CERT_STATUS: (VALID|INVALID)", lines[0])
    token = re.fullmatch(r"X_INCIDENT_TOKEN: (\S+)", lines[1])
    integrity = re.fullmatch(r"FILE_INTEGRITY: (OK|COMPROMISED)", lines[2])
    assert cert, f"Malformed CERT_STATUS line: {lines[0]!r}"
    assert token, f"Malformed X_INCIDENT_TOKEN line: {lines[1]!r}"
    assert integrity, f"Malformed FILE_INTEGRITY line: {lines[2]!r}"
    return cert.group(1), token.group(1), integrity.group(1)


def openssl(*args):
    subprocess.run(
        ["openssl", *map(str, args)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def make_pki(base):
    good_key = base / "trusted-root.key"
    good_ca = base / "trusted-root.crt"
    wrong_key = base / "other-root.key"
    wrong_ca = base / "other-root.crt"
    server_key = base / "endpoint.key"
    server_csr = base / "endpoint.csr"
    server_crt = base / "endpoint.crt"
    ext = base / "server.ext"

    openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", good_key, "-out", good_ca, "-days", "2",
            "-subj", "/CN=Dynamic Trusted Root",
            "-addext", "basicConstraints=critical,CA:TRUE")
    openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", wrong_key, "-out", wrong_ca, "-days", "2",
            "-subj", "/CN=Unrelated Root",
            "-addext", "basicConstraints=critical,CA:TRUE")
    openssl("req", "-newkey", "rsa:2048", "-nodes",
            "-keyout", server_key, "-out", server_csr,
            "-subj", "/CN=dynamic-endpoint")
    ext.write_text("basicConstraints=critical,CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n")
    openssl("x509", "-req", "-in", server_csr, "-CA", good_ca,
            "-CAkey", good_key, "-CAcreateserial", "-out", server_crt,
            "-days", "2", "-extfile", ext)
    return good_ca, wrong_ca, server_crt, server_key


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for_server(port, proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail("Dynamic HTTPS server exited before accepting connections")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail("Dynamic HTTPS server did not start")


def exercise_case(case_dir, server_crt, server_key, trusted_ca, hash_should_match):
    case_dir.mkdir()
    payload = os.urandom(96) + secrets.token_bytes(17)
    token = "TOK_" + secrets.token_hex(12)
    payload_path = case_dir / "served-update.bin"
    payload_path.write_bytes(payload)
    actual_hash = hashlib.sha256(payload).hexdigest()

    manifest = case_dir / "manifest.sha256"
    entries = [
        hashlib.sha256(secrets.token_bytes(40)).hexdigest(),
        actual_hash if hash_should_match else hashlib.sha256(secrets.token_bytes(41)).hexdigest(),
        hashlib.sha256(secrets.token_bytes(42)).hexdigest(),
    ]
    manifest.write_text("\n".join(f"{h}  update-{i}.bin" for i, h in enumerate(entries)) + "\n")

    port = free_port()
    proc = subprocess.Popen(
        ["python3", "/tmp/dynamic_https_server.py", str(port), str(server_crt),
         str(server_key), str(payload_path), token],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_server(port, proc)
        result = run_script("127.0.0.1", port, trusted_ca, manifest)
        observed = read_strict_report()
        return observed, token, result
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def test_script_exists_and_executable():
    script_path = "/home/user/analyze_endpoint.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_report_exists():
    report_path = "/home/user/investigation_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."


def test_report_contents():
    result = run_script("127.0.0.1", 8443, "/home/user/ca-trust/root.crt", "/home/user/manifest.sha256")
    report_path = "/home/user/investigation_report.txt"
    if not os.path.isfile(report_path):
        pytest.fail(
            f"Report file {report_path} does not exist after running the script. "
            f"stdout={result.stdout!r} stderr={result.stderr!r}"
        )

    with open(report_path, 'r') as f:
        content = f.read()

    # Check CERT_STATUS
    cert_match = re.search(r'^CERT_STATUS:\s*(VALID|INVALID)', content, re.MULTILINE)
    assert cert_match is not None, "CERT_STATUS line is missing or malformed."
    assert cert_match.group(1) == "INVALID", f"Expected CERT_STATUS to be INVALID, but got {cert_match.group(1)}"

    # Check X_INCIDENT_TOKEN
    token_match = re.search(r'^X_INCIDENT_TOKEN:\s*(\S+)', content, re.MULTILINE)
    assert token_match is not None, "X_INCIDENT_TOKEN line is missing or malformed."
    assert token_match.group(1) == "EXFIL_9938_ALPHA", f"Expected X_INCIDENT_TOKEN to be EXFIL_9938_ALPHA, but got {token_match.group(1)}"

    # Check FILE_INTEGRITY
    integrity_match = re.search(r'^FILE_INTEGRITY:\s*(OK|COMPROMISED)', content, re.MULTILINE)
    assert integrity_match is not None, "FILE_INTEGRITY line is missing or malformed."
    assert integrity_match.group(1) == "COMPROMISED", f"Expected FILE_INTEGRITY to be COMPROMISED, but got {integrity_match.group(1)}"


def test_script_handles_dynamic_valid_and_invalid_endpoints(tmp_path):
    good_ca, wrong_ca, server_crt, server_key = make_pki(tmp_path)

    valid_result, valid_token, valid_run = exercise_case(
        tmp_path / "case-one", server_crt, server_key, good_ca, True
    )
    assert valid_result == ("VALID", valid_token, "OK"), (
        f"Valid-chain/matching-manifest case failed: {valid_result}; "
        f"stdout={valid_run.stdout!r} stderr={valid_run.stderr!r}"
    )

    invalid_result, invalid_token, invalid_run = exercise_case(
        tmp_path / "case-two", server_crt, server_key, wrong_ca, False
    )
    assert invalid_result == ("INVALID", invalid_token, "COMPROMISED"), (
        f"Invalid-chain/nonmatching-manifest case failed: {invalid_result}; "
        f"stdout={invalid_run.stdout!r} stderr={invalid_run.stderr!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
