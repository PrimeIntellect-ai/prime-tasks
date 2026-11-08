#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import socket
import ssl
import string
import subprocess
import time

import pytest

ROOT = "/app/jwt-service"
BINARY = ROOT + "/jwt_server"
EXPECTED_SECRET = "X9fR2mP7qL4cT1vN8bH5wK3zJ6yD0sA!"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 15)
    return subprocess.run(cmd, **kwargs)


def test_secret_key_extracted():
    secret_path = ROOT + "/secret.key"
    assert os.path.isfile(secret_path), f"Secret key file not found at {secret_path}"
    with open(secret_path, "r") as f:
        secret = f.read().strip()
    assert secret == EXPECTED_SECRET, f"Secret key extracted is incorrect. Expected {EXPECTED_SECRET}, got {secret}"


def test_tls_certificates_exist_and_are_valid_rsa2048_pair():
    cert_path = ROOT + "/tls/cert.pem"
    key_path = ROOT + "/tls/key.pem"
    assert os.path.isfile(cert_path), f"TLS certificate not found at {cert_path}"
    assert os.path.isfile(key_path), f"TLS private key not found at {key_path}"
    assert os.path.getsize(cert_path) > 0, "TLS certificate is empty"
    assert os.path.getsize(key_path) > 0, "TLS private key is empty"

    cert_check = run(["openssl", "x509", "-in", cert_path, "-noout", "-text"])
    assert cert_check.returncode == 0, f"Invalid X.509 certificate: {cert_check.stderr}"
    assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_check.stdout), "Certificate does not contain a 2048-bit key"

    key_check = run(["openssl", "pkey", "-in", key_path, "-passin", "pass:", "-check", "-noout"])
    assert key_check.returncode == 0, f"Invalid or encrypted private key: {key_check.stderr}"

    cert_pub = run(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    key_pub = run(["openssl", "pkey", "-in", key_path, "-passin", "pass:", "-pubout"])
    assert cert_pub.returncode == 0 and key_pub.returncode == 0
    assert cert_pub.stdout.strip() == key_pub.stdout.strip(), "TLS certificate and private key do not match"

    subject = run(["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"])
    issuer = run(["openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253"])
    assert subject.returncode == 0 and issuer.returncode == 0
    assert subject.stdout.partition("=")[2].strip() == issuer.stdout.partition("=")[2].strip(), "Certificate is not self-signed"
    verify = run(["openssl", "verify", "-CAfile", cert_path, cert_path])
    assert verify.returncode == 0, f"Self-signed certificate verification failed: {verify.stdout} {verify.stderr}"
    valid_now = run(["openssl", "x509", "-in", cert_path, "-checkend", "1", "-noout"])
    assert valid_now.returncode == 0, "TLS certificate is expired or not currently usable"


def test_makefile_fixed():
    makefile_path = ROOT + "/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-lssl" in content, "Makefile is missing -lssl linker flag"
    assert "-lcrypto" in content, "Makefile is missing -lcrypto linker flag"


def test_auth_cpp_vulnerability_patched(tmp_path):
    auth_cpp_path = ROOT + "/src/auth.cpp"
    assert os.path.isfile(auth_cpp_path), f"auth.cpp not found at {auth_cpp_path}"

    harness = tmp_path / "test_auth.cpp"
    harness.write_text(r'''#include <iostream>
#include <string>
#include "auth.h"
int main() {
    std::string secret, token;
    while (std::getline(std::cin, secret)) {
        if (!std::getline(std::cin, token)) return 2;
        std::cout << (verify_jwt(token, secret) ? "1" : "0") << std::endl;
    }
    return 0;
}
''')
    binary = tmp_path / "test_auth"
    compiled = run([
        "g++", "-std=c++11", str(harness), auth_cpp_path,
        "-I" + ROOT + "/src", "-o", str(binary)
    ])
    assert compiled.returncode == 0, f"Failed to compile test program against auth.cpp:\n{compiled.stderr}"

    cases = [
        (EXPECTED_SECRET, "header.payload.alg=none", False),
        (EXPECTED_SECRET, "header.payload.alg=NONE", False),
        (EXPECTED_SECRET, "header.payload." + EXPECTED_SECRET, True),
    ]
    alphabet = string.ascii_letters + string.digits
    for _ in range(24):
        secret = "".join(secrets.choice(alphabet) for _ in range(secrets.choice(range(18, 43))))
        prefix = "hdr" + secrets.token_hex(7) + ".payload" + secrets.token_hex(9)
        cases.append((secret, prefix + "." + secret, True))
        cases.append((secret, prefix + ".bad-" + secrets.token_hex(12), False))
        alg = secrets.choice(["none", "NONE"])
        cases.append((secret, prefix + ".alg=" + alg + "." + secrets.token_hex(8), False))
        # Algorithm none must remain rejected even if the text happens to end in the secret.
        cases.append((secret, prefix + ".alg=" + alg + "." + secret, False))

    stdin = "".join(secret + "\n" + token + "\n" for secret, token, _ in cases)
    checked = run([str(binary)], input=stdin)
    assert checked.returncode == 0, f"Authentication harness failed: {checked.stderr}"
    answers = checked.stdout.splitlines()
    assert len(answers) == len(cases), "Authentication implementation did not answer every generated case"
    for index, ((_, token, expected), answer) in enumerate(zip(cases, answers)):
        assert answer in ("0", "1"), f"Malformed result for authentication case {index}"
        assert (answer == "1") == expected, f"Incorrect authentication result for generated token {token!r}"


def listener_inodes(require_any_address=True):
    found = set()
    path = "/proc/net/tcp"
    with open(path, "r") as f:
        next(f, None)
        for line in f:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            address, port = local.split(":")
            if int(port, 16) == 8443 and state == "0A":
                if not require_any_address or address == "00000000":
                    found.add(inode)
    return found


def listener_pids(inodes):
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            exe = os.readlink(f"/proc/{entry}/exe")
            if exe != BINARY:
                continue
            for fd in os.listdir(f"/proc/{entry}/fd"):
                try:
                    target = os.readlink(f"/proc/{entry}/fd/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def tls_handshake():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 8443), timeout=4) as raw:
        with context.wrap_socket(raw, server_hostname="localhost") as wrapped:
            assert wrapped.version(), "No TLS version was negotiated"
            assert wrapped.getpeercert(binary_form=True), "Service did not present a TLS certificate"


def wait_for_service(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        inodes = listener_inodes()
        owners = listener_pids(inodes)
        if owners:
            try:
                tls_handshake()
                return owners
            except (OSError, ssl.SSLError):
                pass
        time.sleep(0.2)
    return set()


def test_service_compiled_linked_and_running_on_8443():
    # First verify that the agent actually left this service, rather than an unrelated
    # process, serving TLS on the required all-interface port.
    old_owners = listener_pids(listener_inodes())
    assert old_owners, "jwt_server was not left running on 0.0.0.0:8443"
    tls_handshake()

    # Stop the submitted instance so the verifier can rebuild and execute the artifact itself.
    for pid in old_owners:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in old_owners:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    cleaned = run(["make", "clean"], cwd=ROOT)
    assert cleaned.returncode == 0, f"make clean failed:\n{cleaned.stdout}\n{cleaned.stderr}"

    dry_run = run(["make", "-n", "all"], cwd=ROOT)
    assert dry_run.returncode == 0, f"Makefile dry run failed:\n{dry_run.stderr}"
    link_lines = [line for line in dry_run.stdout.splitlines() if "jwt_server" in line and "-o" in line]
    assert link_lines, "Makefile does not contain a jwt_server link recipe"
    assert any("-lssl" in line and "-lcrypto" in line for line in link_lines), "Actual jwt_server link recipe is missing -lssl or -lcrypto"

    built = run(["make", "all"], cwd=ROOT, timeout=30)
    assert built.returncode == 0, f"Service did not build successfully:\n{built.stdout}\n{built.stderr}"
    assert os.path.isfile(BINARY), f"Compiled binary not found at {BINARY}. Did you run make?"
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable"
    elf = run(["readelf", "-h", BINARY])
    assert elf.returncode == 0 and "ELF Header" in elf.stdout, "jwt_server is not a valid ELF executable"

    subprocess.Popen(
        [BINARY], cwd=ROOT, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    new_owners = wait_for_service()
    assert new_owners, "Freshly rebuilt jwt_server did not start a TLS listener on 0.0.0.0:8443"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
