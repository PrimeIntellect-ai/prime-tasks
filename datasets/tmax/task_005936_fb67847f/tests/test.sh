#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import ssl
import socket
import subprocess
import threading
import queue
import secrets

BASE = "/home/user/forensics"
BINARY = os.path.join(BASE, "malware_fixed")
SOURCE = os.path.join(BASE, "exfil_malware.cpp")
DUMP = os.path.join(BASE, "dump.bin")
CERT = os.path.join(BASE, "c2_cert.pem")
KEY = os.path.join(BASE, "c2_key.pem")


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=20, **kwargs)


def exercise_tls_client(executable):
    token_a = secrets.token_hex(20)
    token_b = secrets.token_hex(20)
    lines = [
        f"DYNAMIC-{token_a}:" + "A" * 180,
        f"DYNAMIC-{token_b}:" + "B" * 220,
    ]
    expected = ("\n".join(lines) + "\n").encode()

    with open(DUMP, "rb") as f:
        original_dump = f.read()

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(CERT, KEY)
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 8443))
    listener.listen(1)
    listener.settimeout(10)
    result = queue.Queue()

    def receive():
        data = bytearray()
        try:
            conn, _ = listener.accept()
            conn.settimeout(10)
            with conn:
                with context.wrap_socket(conn, server_side=True) as tls:
                    while True:
                        chunk = tls.recv(4096)
                        if not chunk:
                            break
                        data.extend(chunk)
            result.put((bytes(data), None))
        except BaseException as exc:
            result.put((bytes(data), repr(exc)))
        finally:
            listener.close()

    thread = threading.Thread(target=receive, daemon=True)
    try:
        with open(DUMP, "wb") as f:
            f.write(expected[:-1])
        thread.start()
        proc = subprocess.run([executable], cwd=BASE, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=15)
        thread.join(12)
        assert not thread.is_alive(), "TLS interception did not complete."
        received, error = result.get_nowait()
        assert error is None, f"TLS listener failed: {error}"
        assert proc.returncode == 0, (
            f"{executable} exited with {proc.returncode}: "
            f"{proc.stderr.decode(errors='replace')}"
        )
        assert received == expected, (
            "The malware did not transmit both complete dynamically generated "
            "payloads over TLS; a payload may still be truncated or fabricated."
        )
    finally:
        with open(DUMP, "wb") as f:
            f.write(original_dump)
        listener.close()


def test_malware_fixed_exists_and_executable():
    """Verify that the fixed malware is a compiled executable."""
    filepath = BINARY
    assert os.path.isfile(filepath), f"Expected executable at {filepath} is missing."
    st = os.stat(filepath)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {filepath} is not executable."
    with open(filepath, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{filepath} is not a compiled ELF binary."


def test_patched_source_compiles_and_both_binaries_handle_long_payloads():
    rebuilt = "/tmp/rebuilt_malware"
    compile_result = run([
        "g++", "-o", rebuilt, SOURCE, "-lssl", "-lcrypto"
    ])
    assert compile_result.returncode == 0, (
        "The patched C++ source does not compile: " + compile_result.stderr
    )
    exercise_tls_client(rebuilt)
    exercise_tls_client(BINARY)


def test_tls_certificates_exist_and_are_valid():
    """Verify the certificate/key are a matching self-signed RSA-2048 pair."""
    assert os.path.isfile(CERT), f"Certificate file {CERT} is missing."
    assert os.path.isfile(KEY), f"Private key file {KEY} is missing."

    cert_check = run(["openssl", "x509", "-in", CERT, "-noout"])
    assert cert_check.returncode == 0, cert_check.stderr
    key_check = run(["openssl", "rsa", "-in", KEY, "-check", "-noout"])
    assert key_check.returncode == 0, key_check.stderr

    key_text = run(["openssl", "pkey", "-in", KEY, "-text", "-noout"])
    assert key_text.returncode == 0, key_text.stderr
    assert re.search(r"Private-Key:\s*\(2048 bit", key_text.stdout), \
        "The private key is not RSA-2048."

    cert_pub = run(["openssl", "x509", "-in", CERT, "-pubkey", "-noout"])
    key_pub = run(["openssl", "pkey", "-in", KEY, "-pubout"])
    assert cert_pub.returncode == 0 and key_pub.returncode == 0
    assert cert_pub.stdout.strip() == key_pub.stdout.strip(), \
        "The certificate and private key do not match."

    names = run(["openssl", "x509", "-in", CERT, "-noout", "-subject", "-issuer",
                 "-nameopt", "RFC2253"])
    assert names.returncode == 0, names.stderr
    fields = [line.split("=", 1)[1] for line in names.stdout.splitlines() if "=" in line]
    assert len(fields) == 2 and fields[0] == fields[1], \
        "The certificate is not self-signed."
    verify = run(["openssl", "verify", "-CAfile", CERT, CERT])
    assert verify.returncode == 0, verify.stderr


def test_run_isolated_script():
    """Verify that the isolation script contains the required real commands."""
    filepath = os.path.join(BASE, "run_isolated.sh")
    assert os.path.isfile(filepath), f"Script {filepath} is missing."
    with open(filepath, "r") as f:
        content = f.read()
    assert "unshare" in content, f"Script {filepath} does not contain the 'unshare' command."

    syntax = run(["bash", "-n", filepath])
    assert syntax.returncode == 0, f"Isolation script has invalid shell syntax: {syntax.stderr}"
    commands = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    assert re.search(r"\bunshare\s+-r\s+-n\b", commands), \
        "Isolation script must invoke unshare -r -n."
    assert re.search(r"\bip\s+link\s+set\s+lo\s+up\b", commands), \
        "Isolation script must bring up the namespace loopback interface."
    assert re.search(r"(?:^|[;&|\s])(?:\./)?malware_fixed(?:\s|$)", commands), \
        "Isolation script must execute ./malware_fixed."


def test_interception_and_final_evidence_redaction():
    """Verify captured records and exact redaction of the captured material."""
    raw_path = os.path.join(BASE, "intercepted.raw")
    final_path = os.path.join(BASE, "final_evidence.log")
    assert os.path.isfile(raw_path), f"Intercepted data {raw_path} is missing."
    assert os.path.isfile(final_path), f"Final evidence log {final_path} is missing."

    with open(raw_path, "r", errors="strict") as f:
        raw = f.read()
    with open(final_path, "r", errors="strict") as f:
        content = f.read()
    with open(DUMP, "r", errors="strict") as f:
        source_lines = f.read().splitlines()

    for line in source_lines:
        assert line in raw, "intercepted.raw does not contain a complete exfiltrated record."

    ssn_pattern = re.compile(r"\b\d{3}-\d{2}-\d{4}\b")
    expected_redaction = ssn_pattern.sub("REDACTED-SSN", raw)
    assert content == expected_redaction, \
        "final_evidence.log is not the exact SSN-redacted form of intercepted.raw."

    # Preserve the original final-evidence assertions.
    assert "123-45-6789" not in content, "Original SSN '123-45-6789' was not redacted."
    assert "987-65-4321" not in content, "Original SSN '987-65-4321' was not redacted."
    assert "REDACTED-SSN" in content, "The string 'REDACTED-SSN' was not found in the output."
    assert "USER: alice" in content, "Data for 'alice' is missing from the final log."
    assert "USER: bob" in content, "Data for 'bob' is missing from the final log."
    assert "EXTRA_DATA_TO_TRIGGER_OVERFLOW: AAAAA" in content, \
        "Overflow payload data was truncated or missing."
    assert "EXTRA_DATA_TO_TRIGGER_OVERFLOW: BBBBB" in content, \
        "Overflow payload data was truncated or missing."
    assert not ssn_pattern.search(content), "Found unredacted SSN patterns in the final log."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
