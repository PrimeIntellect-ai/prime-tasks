#!/bin/bash
set -e
mkdir -p /logs/verifier

# Make the legacy executable unavailable while behavioral tests run. A genuine
# reimplementation does not need it after the agent has started the daemon.
held_oracle=""
if [ -e /app/token_validator ]; then
    held_oracle="/tmp/token_validator.verifier-held.$$"
    mv /app/token_validator "$held_oracle"
fi
cleanup() {
    if [ -n "$held_oracle" ] && [ -e "$held_oracle" ]; then
        mv "$held_oracle" /app/token_validator
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import ssl
import stat
import subprocess
from pathlib import Path

import pytest


def generate_client_cert(cn, prefix):
    key_path = f"/tmp/{prefix}.key"
    csr_path = f"/tmp/{prefix}.csr"
    crt_path = f"/tmp/{prefix}.crt"

    subprocess.run([
        "openssl", "req", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key_path, "-out", csr_path,
        "-subj", f"/CN={cn}"
    ], check=True, capture_output=True)

    subprocess.run([
        "openssl", "x509", "-req", "-in", csr_path,
        "-CA", "/app/certs/ca.crt", "-CAkey", "/app/certs/ca.key",
        "-CAcreateserial", "-out", crt_path, "-days", "1"
    ], check=True, capture_output=True)

    return crt_path, key_path


def admin_context(prefix="admin_random"):
    crt, key = generate_client_cert("Rotation-Admin", prefix)
    context = ssl.create_default_context(
        ssl.Purpose.SERVER_AUTH, cafile="/app/certs/ca.crt"
    )
    context.load_cert_chain(certfile=crt, keyfile=key)
    return context


def request(context, service, token):
    with socket.create_connection(("127.0.0.1", 8443), timeout=2) as sock:
        with context.wrap_socket(sock, server_hostname="localhost") as ssock:
            ssock.settimeout(2)
            ssock.sendall(f"ROTATE {service} {token}\n".encode("ascii"))
            data = b""
            while b"\n" not in data:
                chunk = ssock.recv(1024)
                if not chunk:
                    break
                data += chunk
            return data.decode("ascii")


def listener_pids():
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1].upper() == "0100007F:20FB" and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
        except OSError:
            continue
    return pids


def find_server_sources():
    candidates = []
    for root in ("/home/user", "/app", "/root", "/tmp"):
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {"certs", "__pycache__", ".git"}]
            for name in files:
                if not name.endswith(".c"):
                    continue
                path = os.path.join(current, name)
                try:
                    text = Path(path).read_text(errors="ignore")
                except OSError:
                    continue
                if "8443" in text and "ROTATE" in text and "SSL_" in text:
                    candidates.append((path, text))
    return candidates


def test_native_c_openssl_daemon_and_no_external_validator_calls():
    pids = listener_pids()
    assert pids, "No process is listening on 127.0.0.1:8443"

    native = []
    for pid in pids:
        proc_exe = f"/proc/{pid}/exe"
        try:
            with open(proc_exe, "rb") as f:
                magic = f.read(4)
            exe_path = os.readlink(proc_exe).replace(" (deleted)", "")
            maps = Path(f"/proc/{pid}/maps").read_text(errors="ignore")
        except OSError:
            continue
        if magic == b"\x7fELF" and not exe_path.startswith(("/usr/", "/bin/", "/sbin/")) and "libssl.so" in maps:
            native.append((pid, proc_exe))

    assert native, "The listener must be a submitted native ELF daemon using libssl"

    sources = find_server_sources()
    assert sources, "Could not find the C source for the OpenSSL server"
    forbidden_source = re.compile(
        r"/app/token_validator|\b(?:system|popen|execl|execle|execlp|execv|execve|execvp|posix_spawn|posix_spawnp)\s*\("
    )
    assert any(not forbidden_source.search(text) for _, text in sources), \
        "C server source invokes the legacy validator or an external process"

    for _, proc_exe in native:
        strings = subprocess.run(
            ["strings", proc_exe], text=True, capture_output=True, check=False
        ).stdout
        assert "/app/token_validator" not in strings, \
            "Running daemon embeds the legacy validator path"
        symbols = subprocess.run(
            ["nm", "-D", proc_exe], text=True, capture_output=True, check=False
        ).stdout
        assert not re.search(
            r"\b(?:system|popen|execl|execle|execlp|execv|execve|execvp|posix_spawn|posix_spawnp)(?:@|$)",
            symbols,
            re.MULTILINE,
        ), "Running daemon imports a prohibited process-execution function"


def test_no_client_cert():
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile="/app/certs/ca.crt")
    # Do not load client certificate
    try:
        with socket.create_connection(('127.0.0.1', 8443), timeout=2) as sock:
            with context.wrap_socket(sock, server_hostname='localhost') as ssock:
                ssock.sendall(b"ROTATE test AA000000000000E8\n")
                ssock.recv(1024)
        pytest.fail("Connection should have been rejected without a client certificate")
    except (ssl.SSLError, ConnectionResetError, socket.error):
        pass # Expected


def test_bad_cn():
    crt, key = generate_client_cert("Hacker", "bad")
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile="/app/certs/ca.crt")
    context.load_cert_chain(certfile=crt, keyfile=key)

    try:
        with socket.create_connection(('127.0.0.1', 8443), timeout=2) as sock:
            with context.wrap_socket(sock, server_hostname='localhost') as ssock:
                ssock.sendall(b"ROTATE test AA000000000000E8\n")
                ssock.recv(1024)
        pytest.fail("Connection should have been rejected or dropped due to incorrect CN")
    except (ssl.SSLError, ConnectionResetError, socket.error):
        pass # Expected


def test_valid_admin_invalid_token():
    crt, key = generate_client_cert("Rotation-Admin", "admin_invalid")
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile="/app/certs/ca.crt")
    context.load_cert_chain(certfile=crt, keyfile=key)

    with socket.create_connection(('127.0.0.1', 8443), timeout=2) as sock:
        with context.wrap_socket(sock, server_hostname='localhost') as ssock:
            # Token starts with AA, but XOR sum is not 0x42
            ssock.sendall(b"ROTATE db AA11223344556677\n")
            resp = ssock.recv(1024).decode()
            assert resp == "ERR INVALID_TOKEN\n", f"Expected ERR INVALID_TOKEN\\n, got: {repr(resp)}"


def test_valid_admin_valid_token():
    crt, key = generate_client_cert("Rotation-Admin", "admin_valid")
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile="/app/certs/ca.crt")
    context.load_cert_chain(certfile=crt, keyfile=key)

    with socket.create_connection(('127.0.0.1', 8443), timeout=2) as sock:
        with context.wrap_socket(sock, server_hostname='localhost') as ssock:
            # Valid token: Starts with AA, XOR sum is 0x42
            ssock.sendall(b"ROTATE web AA000000000000E8\n")
            resp = ssock.recv(1024).decode()

            assert resp.startswith("OK "), f"Expected response starting with 'OK ', got: {repr(resp)}"
            parts = resp.strip().split()
            assert len(parts) == 2, "Response should be in format 'OK <password>'"
            password = parts[1]
            assert len(password) == 12, f"Password should be 12 characters, got {len(password)}"
            assert password.isalnum(), "Password should be alphanumeric"

    creds_path = "/home/user/creds.log"
    assert os.path.exists(creds_path), f"Credentials file {creds_path} was not created"

    st = os.stat(creds_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Expected permissions 0600 on {creds_path}, got {oct(perms)}"

    with open(creds_path, "r") as f:
        lines = f.read().splitlines()
        expected_entry = f"web:{password}"
        assert expected_entry in lines, f"Expected entry '{expected_entry}' not found in {creds_path}"


def valid_token():
    values = [0xAA] + [secrets.randbelow(256) for _ in range(6)]
    last = 0x42
    for value in values:
        last ^= value
    values.append(last)
    token = "".join(f"{value:02x}" if secrets.randbits(1) else f"{value:02X}" for value in values)
    return token


def wrong_xor_token():
    values = [0xAA] + [secrets.randbelow(256) for _ in range(7)]
    xor_value = 0
    for value in values:
        xor_value ^= value
    if xor_value == 0x42:
        values[-1] ^= 1
    return "".join(f"{value:02X}" for value in values)


def wrong_prefix_token_with_correct_xor():
    first = secrets.choice([x for x in range(256) if x != 0xAA])
    values = [first] + [secrets.randbelow(256) for _ in range(6)]
    last = 0x42
    for value in values:
        last ^= value
    values.append(last)
    return "".join(f"{value:02X}" for value in values)


def test_randomized_token_logic_passwords_and_log_entries():
    context = admin_context()
    generated_passwords = []
    expected_entries = []

    for i in range(12):
        service = f"random-valid-{secrets.token_hex(5)}-{i}"
        response = request(context, service, valid_token())
        assert re.fullmatch(r"OK [A-Za-z0-9]{12}\n", response), repr(response)
        password = response[3:-1]
        generated_passwords.append(password)
        expected_entries.append(f"{service}:{password}")

    assert len(set(generated_passwords)) == len(generated_passwords), \
        "Each accepted rotation must generate a new random password"

    invalid_tokens = []
    for _ in range(8):
        invalid_tokens.append(wrong_xor_token())
        invalid_tokens.append(wrong_prefix_token_with_correct_xor())

    malformed = valid_token()
    invalid_tokens.extend([
        malformed[:-1],
        malformed + "0",
        malformed[:secrets.randbelow(16)] + "G" + malformed[secrets.randbelow(16) + 1:],
        "Z" * 16,
    ])

    for i, token in enumerate(invalid_tokens):
        response = request(context, f"random-invalid-{i}", token)
        assert response == "ERR INVALID_TOKEN\n", \
            f"Token {token!r} should be rejected, got {response!r}"

    creds_path = "/home/user/creds.log"
    assert os.path.exists(creds_path)
    assert stat.S_IMODE(os.stat(creds_path).st_mode) == 0o600
    with open(creds_path, "r") as f:
        lines = f.read().splitlines()
    for entry in expected_entries:
        assert entry in lines, f"Expected randomized credential entry {entry!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
