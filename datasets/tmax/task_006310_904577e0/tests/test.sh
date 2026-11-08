#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import http.server
import os
import re
import secrets
import socket
import ssl
import subprocess
import tempfile
import threading
import time

import pytest

PAYLOAD = "/home/user/payload.py"
OUTPUT = "/home/user/extracted_command.txt"
FIREWALL = "/home/user/recon/firewall_dump.txt"
C2_SERVER = "/home/user/c2_server.py"
ROOT_CA = "/home/user/certs/RootCA.crt"
ROOT_KEY = "/home/user/certs/RootCA.key"


def test_payload_script_exists():
    assert os.path.isfile(PAYLOAD), (
        f"The payload script {PAYLOAD} was not found. You must create it to complete the task."
    )


def allowed_c2_port():
    with open(FIREWALL, "r", encoding="utf-8") as f:
        rules = f.read().splitlines()

    accepted = []
    for line in rules:
        if re.search(r"^-A OUTPUT\b", line) and re.search(r"(?:^|\s)-p tcp(?:\s|$)", line) and re.search(r"(?:^|\s)-j ACCEPT(?:\s|$)", line):
            match = re.search(r"--dport\s+(\d+)\b", line)
            if match:
                accepted.append(int(match.group(1)))

    # TCP/53 is the explicitly permitted DNS service, not the internal HTTPS C2 service.
    c2_ports = [port for port in accepted if port != 53]
    assert len(c2_ports) == 1, f"Expected exactly one non-DNS TCP egress port, found {c2_ports}"
    return c2_ports[0]


def stop_existing_c2():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                argv = [part.decode(errors="ignore") for part in f.read().split(b"\0") if part]
            if len(argv) >= 2 and argv[0].endswith("python3") and argv[1] == C2_SERVER:
                os.kill(int(entry), 15)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.2)


def make_certificates(directory):
    signed_key = os.path.join(directory, "signed.key")
    signed_csr = os.path.join(directory, "signed.csr")
    signed_cert = os.path.join(directory, "signed.crt")
    untrusted_key = os.path.join(directory, "untrusted.key")
    untrusted_cert = os.path.join(directory, "untrusted.crt")
    config = os.path.join(directory, "cert.cnf")

    with open(config, "w", encoding="utf-8") as f:
        f.write("""[req]
prompt=no
distinguished_name=dn
req_extensions=v3
x509_extensions=v3
[dn]
CN=c2.internal.thm
[v3]
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
subjectAltName=@alt
[alt]
DNS.1=c2.internal.thm
IP.1=127.0.0.1
""")

    subprocess.run(
        ["openssl", "req", "-new", "-nodes", "-newkey", "rsa:2048",
         "-keyout", signed_key, "-out", signed_csr, "-config", config],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        ["openssl", "x509", "-req", "-in", signed_csr, "-CA", ROOT_CA,
         "-CAkey", ROOT_KEY, "-set_serial", str(secrets.randbits(62) + 1),
         "-out", signed_cert, "-days", "1", "-sha256", "-extfile", config,
         "-extensions", "v3"],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        ["openssl", "req", "-x509", "-nodes", "-newkey", "rsa:2048",
         "-keyout", untrusted_key, "-out", untrusted_cert, "-days", "1",
         "-config", config],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return signed_cert, signed_key, untrusted_cert, untrusted_key


class ReusableHTTPServer(http.server.HTTPServer):
    allow_reuse_address = True


def run_test_server(port, cert, key, command, run_payload=True):
    encoded = base64.b64encode(command.encode("utf-8")).decode("ascii")
    state = {"valid_request": False}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/register" and self.headers.get("Host") == "c2.internal.thm":
                state["valid_request"] = True
                self.send_response(200)
                self.send_header("Set-Cookie", f"C2-Session-Token={encoded}; Path=/; HttpOnly")
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"Registered successfully.")
            else:
                self.send_response(403)
                self.end_headers()

        def log_message(self, *args):
            pass

    server = ReusableHTTPServer(("127.0.0.1", port), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=cert, keyfile=key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        if run_payload:
            returncode, stdout, stderr = execute_payload()
            return state, returncode, stdout, stderr
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def execute_payload():
    try:
        result = subprocess.run(
            ["python3", PAYLOAD],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=15,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"payload.py timed out while contacting the C2 server: {exc}")


def read_output():
    assert os.path.isfile(OUTPUT), f"The output file {OUTPUT} was not created by payload.py."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return f.read().strip()


def wait_for_listener(process, port):
    deadline = time.time() + 5
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail("The supplied C2 server exited before payload.py could connect.")
        sock = socket.socket()
        sock.settimeout(0.1)
        try:
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        finally:
            sock.close()
        time.sleep(0.05)
    pytest.fail(f"The supplied C2 server did not listen on port {port}.")


def test_payload_end_to_end_tls_host_cookie_and_firewall_behavior():
    port = allowed_c2_port()
    stop_existing_c2()

    with tempfile.TemporaryDirectory(prefix="payload-verifier-") as directory:
        signed_cert, signed_key, untrusted_cert, untrusted_key = make_certificates(directory)

        trusted_command = "Execute_Verifier_" + secrets.token_hex(16)
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        state, returncode, stdout, stderr = run_test_server(
            port, signed_cert, signed_key, trusted_command
        )
        assert returncode == 0, f"payload.py failed against a RootCA-signed server: {stderr or stdout}"
        assert state["valid_request"], (
            "payload.py did not request /register with Host: c2.internal.thm on the firewall-allowed port."
        )
        assert read_output() == trusted_command, (
            "payload.py did not extract, Base64-decode, and write the C2-Session-Token cookie."
        )

        # A payload which disables certificate verification would accept this otherwise-identical server.
        untrusted_command = "Untrusted_Verifier_" + secrets.token_hex(16)
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        state, returncode, stdout, stderr = run_test_server(
            port, untrusted_cert, untrusted_key, untrusted_command
        )
        if os.path.isfile(OUTPUT):
            with open(OUTPUT, "r", encoding="utf-8") as f:
                untrusted_output = f.read().strip()
        else:
            untrusted_output = None
        assert not (state["valid_request"] and untrusted_output == untrusted_command), (
            "payload.py accepted an untrusted self-signed TLS certificate; it must validate with RootCA.crt."
        )

    # Finally execute against the supplied C2 server, preserving the original truth check.
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    server = subprocess.Popen(
        ["python3", C2_SERVER, str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_listener(server, port)
        returncode, stdout, stderr = execute_payload()
        assert returncode == 0, f"payload.py failed against c2_server.py: {stderr or stdout}"
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=3)


def test_extracted_command_file_exists():
    path = "/home/user/extracted_command.txt"
    assert os.path.isfile(path), f"The output file {path} was not found. Your payload must create this file."


def test_extracted_command_content():
    c2_server_path = "/home/user/c2_server.py"
    output_path = "/home/user/extracted_command.txt"

    assert os.path.isfile(c2_server_path), f"The C2 server script {c2_server_path} is missing, cannot verify truth data."
    assert os.path.isfile(output_path), f"The output file {output_path} is missing."

    # Derive the expected truth by parsing the C2 server script
    with open(c2_server_path, 'r') as f:
        c2_content = f.read()

    match = re.search(r'C2-Session-Token=([A-Za-z0-9+/=]+)', c2_content)
    assert match is not None, "Could not find the Base64 session token in the C2 server script to derive the expected command."

    base64_token = match.group(1)
    try:
        expected_command = base64.b64decode(base64_token).decode('utf-8')
    except Exception as e:
        pytest.fail(f"Failed to decode the expected Base64 token from the C2 server: {e}")

    # Read the student's output
    with open(output_path, 'r') as f:
        actual_output = f.read().strip()

    assert expected_command in actual_output, (
        f"The file {output_path} does not contain the correct decoded command. "
        f"Expected to find '{expected_command}', but got '{actual_output}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
