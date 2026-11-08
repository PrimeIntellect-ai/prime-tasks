#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import shutil
import socket
import stat
import subprocess
import tempfile
import time

SCRIPT = "/home/user/fetch_data.py"
SECRET = "/home/user/secret.txt"
CA_FILE = "/home/user/ca.crt"


def test_fetch_data_script_exists():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} was not created."


def test_secret_file_exists_and_content():
    assert os.path.isfile(SECRET), f"The file {SECRET} was not created."
    with open(SECRET, "r") as f:
        content = f.read().strip()
    expected_content = "SEC-9988-FLAG-2023"
    assert content == expected_content, f"The content of {SECRET} is incorrect. Expected '{expected_content}', got '{content}'."


def test_secret_file_permissions():
    assert os.path.isfile(SECRET), f"The file {SECRET} does not exist to check permissions."
    permissions = stat.S_IMODE(os.stat(SECRET).st_mode)
    assert permissions == 0o400, f"The file {SECRET} has incorrect permissions. Expected 0o400, got {oct(permissions)}."


def _openssl(*args):
    subprocess.run(["openssl", *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _make_ca_and_server_cert(directory, prefix):
    ca_key = os.path.join(directory, prefix + "-ca.key")
    ca_cert = os.path.join(directory, prefix + "-ca.crt")
    server_key = os.path.join(directory, prefix + "-server.key")
    server_csr = os.path.join(directory, prefix + "-server.csr")
    server_cert = os.path.join(directory, prefix + "-server.crt")
    ext = os.path.join(directory, prefix + "-ext.cnf")
    with open(ext, "w") as f:
        f.write("subjectAltName=IP:127.0.0.1\n")
    _openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
             "-keyout", ca_key, "-out", ca_cert, "-subj", "/CN=Verifier CA " + prefix)
    _openssl("req", "-newkey", "rsa:2048", "-nodes", "-keyout", server_key,
             "-out", server_csr, "-subj", "/CN=127.0.0.1")
    _openssl("x509", "-req", "-in", server_csr, "-CA", ca_cert, "-CAkey", ca_key,
             "-CAcreateserial", "-out", server_cert, "-days", "1", "-extfile", ext)
    return ca_cert, server_cert, server_key


def _write_server(path):
    with open(path, "w") as f:
        f.write(r'''import base64
import hashlib
import http.server
import json
import ssl
import sys

cert, key, data, supplied_hash, record = sys.argv[1:]

class Server(http.server.ThreadingHTTPServer):
    allow_reuse_address = True

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        auth = self.headers.get("Authorization", "")
        valid = False
        details = {"path": self.path, "authorization": auth}
        if self.path == "/admin/data" and auth.startswith("Bearer "):
            token = auth[7:]
            parts = token.split(".")
            try:
                if len(parts) == 3:
                    dec = lambda value: json.loads(base64.urlsafe_b64decode(value + "=" * (-len(value) % 4)))
                    header = dec(parts[0])
                    payload = dec(parts[1])
                    details.update({"header": header, "payload": payload, "signature": parts[2]})
                    valid = (str(header.get("alg", "")).lower() == "none" and
                             payload.get("role") == "admin" and
                             payload.get("user") == "admin" and parts[2] == "")
            except Exception as exc:
                details["decode_error"] = str(exc)
        details["valid"] = valid
        with open(record, "w") as out:
            json.dump(details, out)
        if valid:
            body = json.dumps({"data": data, "sha256": supplied_hash}).encode()
            self.send_response(200)
        else:
            body = json.dumps({"error": "Unauthorized"}).encode()
            self.send_response(401)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

httpd = Server(("127.0.0.1", 8443), Handler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
''')


def _start_server(server_py, cert, key, data, response_hash, record):
    if os.path.exists(record):
        os.unlink(record)
    proc = subprocess.Popen(
        ["python3", server_py, cert, key, data, response_hash, record],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        if proc.poll() is not None:
            raise AssertionError("The verifier HTTPS server could not bind to port 8443")
        try:
            with socket.create_connection(("127.0.0.1", 8443), timeout=0.1):
                return proc
        except OSError:
            time.sleep(0.1)
    proc.terminate()
    raise AssertionError("The verifier HTTPS server did not start")


def _stop_server(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)
    time.sleep(0.2)


def _run_submission():
    return subprocess.run(
        ["runuser", "-u", "user", "--", "python3", SCRIPT],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=25)


def _read_record(path):
    for _ in range(20):
        if os.path.isfile(path):
            with open(path) as f:
                return json.load(f)
        time.sleep(0.1)
    raise AssertionError("The script did not request /admin/data")


def test_script_behavior_jwt_tls_and_integrity():
    original_secret = open(SECRET, "rb").read()
    original_mode = stat.S_IMODE(os.stat(SECRET).st_mode)
    work = tempfile.mkdtemp(prefix="fetch-data-verifier-")
    original_ca = os.path.join(work, "original-ca.crt")
    shutil.copy2(CA_FILE, original_ca)
    server_py = os.path.join(work, "server.py")
    _write_server(server_py)

    subprocess.run(["pkill", "-f", "/home/user/api_server.py"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    proc = None
    try:
        trusted_ca, trusted_cert, trusted_key = _make_ca_and_server_cert(work, "trusted")
        _, untrusted_cert, untrusted_key = _make_ca_and_server_cert(work, "untrusted")
        shutil.copyfile(trusted_ca, CA_FILE)
        os.chmod(CA_FILE, 0o644)

        # A fresh unpredictable response proves the script, rather than a hardcoded answer,
        # obtains the data and constructs the required alg=none admin JWT.
        dynamic_secret = "VERIFIER-" + os.urandom(24).hex()
        good_hash = hashlib.sha256(dynamic_secret.encode()).hexdigest()
        record = os.path.join(work, "good-record.json")
        if os.path.exists(SECRET):
            os.unlink(SECRET)
        proc = _start_server(server_py, trusted_cert, trusted_key, dynamic_secret, good_hash, record)
        result = _run_submission()
        _stop_server(proc)
        proc = None
        assert result.returncode == 0, f"fetch_data.py failed against the authenticated API: {result.stderr}"
        request = _read_record(record)
        assert request.get("valid"), "The request did not use an unsigned alg=none JWT with user and role set to admin."
        assert os.path.isfile(SECRET), "The script did not create secret.txt after a valid response."
        with open(SECRET, "rb") as f:
            assert f.read() == dynamic_secret.encode(), "secret.txt must contain only the data returned by the API."
        assert stat.S_IMODE(os.stat(SECRET).st_mode) == 0o400, "The script did not set secret.txt permissions to exactly 0400."

        # A mismatched digest must not be accepted or written.
        bad_secret = "BADHASH-" + os.urandom(24).hex()
        record = os.path.join(work, "bad-hash-record.json")
        os.unlink(SECRET)
        proc = _start_server(server_py, trusted_cert, trusted_key, bad_secret, "0" * 64, record)
        _run_submission()
        _stop_server(proc)
        proc = None
        assert _read_record(record).get("valid"), "The integrity test did not receive the required authenticated request."
        assert not os.path.exists(SECRET), "The script wrote secret.txt even though the response SHA-256 was invalid."

        # A certificate not signed by /home/user/ca.crt must be rejected.
        record = os.path.join(work, "untrusted-record.json")
        proc = _start_server(server_py, untrusted_cert, untrusted_key,
                             "UNTRUSTED-" + os.urandom(16).hex(), "0" * 64, record)
        _run_submission()
        _stop_server(proc)
        proc = None
        assert not os.path.exists(record), "The script sent an HTTP request despite the server certificate being untrusted."
        assert not os.path.exists(SECRET), "The script created secret.txt after an untrusted TLS connection."
    finally:
        if proc is not None:
            _stop_server(proc)
        shutil.copyfile(original_ca, CA_FILE)
        with open(SECRET, "wb") as f:
            f.write(original_secret)
        os.chmod(SECRET, original_mode)
        shutil.rmtree(work, ignore_errors=True)
        subprocess.run(["/home/user/start_server.sh"], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
