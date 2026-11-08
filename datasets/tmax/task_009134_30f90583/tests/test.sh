#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import signal
import socket
import ssl
import subprocess
import time

EXPECTED = b"<h1>Welcome to the secure app</h1>\n"
APP_DIR = "/home/user/containers/app1"
WWW = APP_DIR + "/www"
PID_FILE = APP_DIR + "/server.pid"
CERT = "/home/user/certs/cert.pem"
KEY = "/home/user/certs/key.pem"


def run_openssl(*args):
    return subprocess.run(
        ["openssl", *args], stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=True
    ).stdout


def read_live_pid():
    assert os.path.isfile(PID_FILE), f"PID file not found at {PID_FILE}. Did the manager script start the server?"
    with open(PID_FILE, "r") as f:
        value = f.read().strip()
    assert value.isdigit(), f"Invalid PID found in {PID_FILE}: {value}"
    pid = int(value)
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running. The server might have crashed."
    stat = open(f"/proc/{pid}/stat").read().split()
    assert stat[2] != "Z", f"Process with PID {pid} is a zombie."
    return pid


def assert_server_process(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    expected_args = ["/home/user/server.py", "8443", CERT, KEY]
    assert len(argv) >= 5 and argv[-4:] == expected_args, \
        f"PID {pid} is not the required TLS server process; argv was {argv}"

    cwd = os.path.realpath(f"/proc/{pid}/cwd")
    assert cwd == os.path.realpath(WWW), \
        f"Server working directory is {cwd}, not {WWW}"


def fetch_https():
    last_error = None
    for _ in range(50):
        try:
            context = ssl._create_unverified_context()
            with socket.create_connection(("127.0.0.1", 8443), timeout=2) as raw:
                with context.wrap_socket(raw, server_hostname="localhost") as tls:
                    peer_der = tls.getpeercert(binary_form=True)
                    tls.sendall(b"GET /index.html HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
                    response = b""
                    while True:
                        chunk = tls.recv(65536)
                        if not chunk:
                            break
                        response += chunk
            header, body = response.split(b"\r\n\r\n", 1)
            assert header.startswith(b"HTTP/1.0 200") or header.startswith(b"HTTP/1.1 200"), header
            return body, peer_der
        except (OSError, ssl.SSLError, ValueError) as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Could not fetch index.html from the TLS server: {last_error}")


def validate_symlink():
    assert os.path.islink(WWW) or os.path.isdir(WWW), f"Expected {WWW} to be a valid directory or symlink."
    index_path = os.path.join(WWW, "index.html")
    assert os.path.isfile(index_path), f"Symlink {WWW} does not correctly point to a directory containing index.html."
    with open(index_path, "r") as f:
        content = f.read().strip()
    assert content == "<h1>Welcome to the secure app</h1>", \
        "The index.html served by the symlink does not match the static files content."
    assert os.path.islink(WWW), f"Expected {WWW} to be a symlink."
    assert os.path.realpath(WWW) == os.path.realpath("/home/user/static_files"), \
        f"{WWW} does not point to /home/user/static_files."


def stop_pid(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        if not os.path.exists(f"/proc/{pid}"):
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def test_final_state_and_manager_redeployment():
    verification_path = "/home/user/verification.txt"
    assert os.path.isfile(verification_path), \
        f"Verification file not found at {verification_path}. Did you run curl and save the output?"
    with open(verification_path, "r") as f:
        content = f.read().strip()
    assert "<h1>Welcome to the secure app</h1>" in content, \
        f"Verification file does not contain the expected text. Found: {content}"

    validate_symlink()

    assert os.path.isfile(CERT), f"Certificate file not found at {CERT}."
    assert os.path.isfile(KEY), f"Private key file not found at {KEY}."
    run_openssl("x509", "-in", CERT, "-noout", "-checkend", "0")
    cert_pub = run_openssl("x509", "-in", CERT, "-pubkey", "-noout")
    key_pub = run_openssl("pkey", "-in", KEY, "-pubout")
    assert cert_pub == key_pub, "Certificate and private key do not match."
    subject = run_openssl("x509", "-in", CERT, "-noout", "-subject").decode().split("=", 1)[-1].strip()
    issuer = run_openssl("x509", "-in", CERT, "-noout", "-issuer").decode().split("=", 1)[-1].strip()
    assert subject == issuer, "Certificate is not self-signed."
    run_openssl("verify", "-CAfile", CERT, CERT)

    pid = read_live_pid()
    assert_server_process(pid)
    body, peer_der = fetch_https()
    cert_der = run_openssl("x509", "-in", CERT, "-outform", "DER")
    assert peer_der == cert_der, "The server is not presenting /home/user/certs/cert.pem."
    assert body == EXPECTED, f"HTTPS server returned unexpected content: {body!r}"
    with open(verification_path, "rb") as f:
        assert f.read() == body, "verification.txt is not the exact output returned by the HTTPS server."

    # Prove manager.sh itself is fixed by removing the deployment and starting it afresh.
    stop_pid(pid)
    shutil.rmtree(APP_DIR)
    result = subprocess.run(
        ["/home/user/manager.sh", "start", "app1"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, f"manager.sh start failed: {result.stderr.decode(errors='replace')}"

    validate_symlink()
    new_pid = read_live_pid()
    assert_server_process(new_pid)
    new_body, new_peer_der = fetch_https()
    assert new_peer_der == cert_der, "Freshly deployed server is not presenting the generated certificate."
    assert new_body == EXPECTED, f"Freshly deployed HTTPS server returned unexpected content: {new_body!r}"

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
