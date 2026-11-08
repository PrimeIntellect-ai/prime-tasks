#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import glob
import os
import re
import secrets
import socket
import ssl
import subprocess
import time
import pytest

CERT_DIR = "/home/user/audit_certs"
KEY_FILE = os.path.join(CERT_DIR, "server.key")
CRT_FILE = os.path.join(CERT_DIR, "server.crt")
LOG_FILE = "/home/user/live_audit.log"


def openssl(*args):
    result = subprocess.run(
        ["openssl", *args], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, result.stderr or result.stdout
    return result.stdout


def recover_keys():
    pairs = []
    with open("/home/user/known_pairs.csv", "r", encoding="utf-8") as f:
        next(f)
        for line in f:
            if line.strip():
                p, c = map(int, line.strip().split(","))
                pairs.append((p, c))

    candidates = []
    for a in range(256):
        if a % 2 == 0:
            continue
        for b in range(256):
            if all((a * p + b) % 256 == c for p, c in pairs):
                candidates.append((a, b))
    assert len(candidates) == 1, f"Known pairs did not uniquely determine keys: {candidates}"
    return candidates[0]


def test_phase1_certificates_exist():
    """Test that valid, matching TLS credentials were generated as requested."""
    assert os.path.isdir(CERT_DIR), f"Directory {CERT_DIR} does not exist."
    assert os.path.isfile(KEY_FILE), f"Private key {KEY_FILE} does not exist."
    assert os.path.isfile(CRT_FILE), f"Certificate {CRT_FILE} does not exist."

    key_text = openssl("pkey", "-in", KEY_FILE, "-check", "-noout", "-text")
    assert re.search(r"Private-Key:\s*\(2048 bit", key_text), "server.key is not an RSA 2048-bit private key."

    key_pub = openssl("pkey", "-in", KEY_FILE, "-pubout")
    cert_pub = openssl("x509", "-in", CRT_FILE, "-pubkey", "-noout")
    assert key_pub.strip() == cert_pub.strip(), "server.key and server.crt do not contain the same public key."

    decoded = ssl._ssl._test_decode_cert(CRT_FILE)
    subject_cns = [value for rdn in decoded["subject"] for name, value in rdn if name == "commonName"]
    assert subject_cns == ["localhost"], f"Certificate CN must be localhost, got {subject_cns}."
    assert decoded["issuer"] == decoded["subject"], "Certificate is not self-signed."
    openssl("verify", "-CAfile", CRT_FILE, CRT_FILE)

    fmt = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(decoded["notBefore"], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(decoded["notAfter"], fmt).replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."
    assert abs((not_after - not_before).total_seconds() - 365 * 24 * 60 * 60) <= 1, "Certificate validity is not 365 days."


def test_phase2_cryptanalysis_script_and_keys():
    """Check that a separate, syntactically valid known-plaintext cryptanalysis script exists."""
    listener = os.path.realpath("/home/user/secure_audit_listener.py")
    candidates = []
    for path in glob.glob("/home/user/**", recursive=True):
        if not os.path.isfile(path) or os.path.realpath(path) == listener:
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                source = f.read()
        except (UnicodeDecodeError, OSError):
            continue
        if path.endswith(".py") or source.startswith("#!") and "python" in source.splitlines()[0].lower():
            try:
                compile(source, path, "exec")
            except SyntaxError:
                continue
            lowered = source.lower()
            if "known_pairs" in lowered and ("256" in source or "%" in source):
                candidates.append(path)

    assert candidates, "No valid Python cryptanalysis script using known_pairs.csv was found."
    assert recover_keys() == (11, 85), "The known plaintext/ciphertext pairs do not recover the required keys."


def test_phase3_historical_decryption():
    """Test that the historical traffic was correctly decrypted."""
    audit_file = "/home/user/historical_audit.txt"
    assert os.path.isfile(audit_file), f"Decrypted file {audit_file} does not exist."

    with open(audit_file, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected = "AUDIT_START: System initialized securely."
    assert content == expected, f"Expected historical audit content to be '{expected}', but got '{content}'."

    a, b = recover_keys()
    inverse = pow(a, -1, 256)
    with open("/home/user/historical_traffic.enc", "rb") as f:
        ciphertext = f.read()
    derived = bytes((inverse * (c - b)) % 256 for c in ciphertext)
    assert derived.decode("utf-8") == content, "Historical output is not the decryption of historical_traffic.enc."


def listener_process_uses_required_script():
    inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, state = fields[1], fields[3]
            if local_address == "0100007F:20FB" and state == "0A":
                inodes.add(fields[9])

    for proc in glob.glob("/proc/[0-9]*"):
        fd_dir = os.path.join(proc, "fd")
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    with open(os.path.join(proc, "cmdline"), "rb") as f:
                        cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
                    if "/home/user/secure_audit_listener.py" in cmdline:
                        return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return False


def send_encrypted_message(message, a, b):
    enc_msg = bytes((a * p + b) % 256 for p in message.encode("utf-8"))
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        with socket.create_connection(("127.0.0.1", 8443), timeout=2) as sock:
            with ctx.wrap_socket(sock, server_hostname="localhost") as ssock:
                ssock.sendall(enc_msg)
    except ConnectionRefusedError:
        pytest.fail("Connection refused on 127.0.0.1:8443. Is the secure_audit_listener.py running?")
    except ssl.SSLError as e:
        pytest.fail(f"SSL error during connection. Is the listener using TLS? Error: {e}")
    except Exception as e:
        pytest.fail(f"Failed to connect to the live audit proxy: {e}")


def newly_appended_text(offset, expected, timeout=3):
    deadline = time.time() + timeout
    data = b""
    while time.time() < deadline:
        if os.path.isfile(LOG_FILE):
            with open(LOG_FILE, "rb") as f:
                f.seek(offset)
                data = f.read()
            if len(data) >= len(expected.encode("utf-8")) + 1:
                break
        time.sleep(0.05)
    return data.decode("utf-8")


def test_phase4_secure_audit_proxy():
    """Exercise the running submitted TLS listener with fixed and unpredictable ciphertexts."""
    script = "/home/user/secure_audit_listener.py"
    assert os.path.isfile(script), f"Listener script {script} does not exist."
    with open(script, "r", encoding="utf-8") as f:
        compile(f.read(), script, "exec")

    a, b = recover_keys()
    initial_size = os.path.getsize(LOG_FILE) if os.path.isfile(LOG_FILE) else 0
    fixed = "LIVE_AUDIT_TEST_PROBE"
    send_encrypted_message(fixed, a, b)
    fixed_delta = newly_appended_text(initial_size, fixed)

    assert os.path.isfile(LOG_FILE), f"Live audit log file {LOG_FILE} does not exist."
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        log_content = f.read()
    assert "LIVE_AUDIT_TEST_PROBE" in log_content, "The live audit proxy did not log the decrypted test message."
    assert fixed_delta == fixed + "\n", "The fixed connection payload was not appended exactly with one newline."

    random_messages = [
        "AUDIT_" + secrets.token_hex(19),
        "SECOND_" + secrets.token_hex(23),
    ]
    for message in random_messages:
        offset = os.path.getsize(LOG_FILE)
        send_encrypted_message(message, a, b)
        delta = newly_appended_text(offset, message)
        assert delta == message + "\n", f"Listener failed to decrypt and append unpredictable payload {message!r}."

    assert listener_process_uses_required_script(), "Port 8443 is not owned by the required secure_audit_listener.py process."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
