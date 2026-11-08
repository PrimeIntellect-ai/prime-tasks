#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import struct
import subprocess
import socket
import ssl
import threading
import random
import tempfile
import pytest

PAYLOAD_PATH = "/home/user/payload"
SOURCE_PATH = "/home/user/payload.cpp"
LOOT_PATH = "/home/user/loot.txt"
CERT_PATH = "/app/server.crt"
KEY_PATH = "/app/server.key"


def test_payload_size_metric():
    """
    Verifier kind: metric_threshold
    Checks that the compiled binary size is <= 35000 bytes.
    """
    assert os.path.isfile(PAYLOAD_PATH), f"Payload binary not found at {PAYLOAD_PATH}"

    size_bytes = os.path.getsize(PAYLOAD_PATH)
    threshold = 35000

    assert size_bytes <= threshold, (
        f"Metric threshold failed: Payload size is {size_bytes} bytes, "
        f"which exceeds the maximum allowed size of {threshold} bytes. "
        "Ensure the binary is compiled with -Os, -s, and stripped of unnecessary sections."
    )


def test_payload_is_compiled_cpp_elf():
    assert os.path.isfile(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    assert os.path.isfile(PAYLOAD_PATH), f"Payload binary not found at {PAYLOAD_PATH}"
    assert os.access(PAYLOAD_PATH, os.X_OK), f"Payload binary at {PAYLOAD_PATH} is not executable"

    with open(PAYLOAD_PATH, "rb") as f:
        header = f.read(20)

    assert len(header) >= 20 and header[:4] == b"\x7fELF", "Payload is not an ELF binary"
    assert header[4] in (1, 2), "Payload has an invalid ELF class"
    assert header[5] in (1, 2), "Payload has invalid ELF byte ordering"
    byte_order = "<" if header[5] == 1 else ">"
    elf_type = struct.unpack(byte_order + "H", header[16:18])[0]
    assert elf_type in (2, 3), "Payload ELF is not an executable or position-independent executable"

    syntax_check = subprocess.run(
        ["g++", "-std=c++17", "-fsyntax-only", SOURCE_PATH],
        capture_output=True,
        text=True,
        timeout=20.0,
    )
    assert syntax_check.returncode == 0, (
        "payload.cpp is not valid C++ source:\n" + syntax_check.stderr
    )


def mock_tls_server(port, secret_message, ready_event, cert_path=CERT_PATH, key_path=KEY_PATH):
    """
    Runs a simple TLS server on the specified port that sends a secret message.
    """
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    try:
        context.load_cert_chain(certfile=cert_path, keyfile=key_path)
    except Exception as e:
        print(f"Failed to load cert chain: {e}")
        ready_event.set()
        return

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(('127.0.0.1', port))
            sock.listen(1)
        except Exception as e:
            print(f"Failed to bind/listen on port {port}: {e}")
            ready_event.set()
            return

        ready_event.set()

        try:
            sock.settimeout(10.0)
            with context.wrap_socket(sock, server_side=True) as ssock:
                conn, addr = ssock.accept()
                with conn:
                    conn.sendall(secret_message.encode('utf-8'))
        except socket.timeout:
            pass
        except Exception as e:
            print(f"Server error during connection: {e}")


def test_rejects_unpinned_certificate():
    """A server using any certificate other than the supplied pinned certificate must be rejected."""
    assert os.path.isfile(PAYLOAD_PATH), f"Payload binary not found at {PAYLOAD_PATH}"
    assert os.access(PAYLOAD_PATH, os.X_OK), f"Payload binary at {PAYLOAD_PATH} is not executable"

    if os.path.exists(LOOT_PATH):
        os.remove(LOOT_PATH)

    with tempfile.TemporaryDirectory() as td:
        bad_cert = os.path.join(td, "untrusted.crt")
        bad_key = os.path.join(td, "untrusted.key")
        generated = subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-days", "1", "-subj", "/CN=localhost",
                "-keyout", bad_key, "-out", bad_cert,
            ],
            capture_output=True,
            text=True,
            timeout=20.0,
        )
        assert generated.returncode == 0, f"Could not generate alternate test certificate: {generated.stderr}"

        target_port = random.randint(8440, 8450)
        decoy = f"FLAG{{unpinned_certificate_{random.randint(100000, 999999)}}}"
        server_ready = threading.Event()
        server_thread = threading.Thread(
            target=mock_tls_server,
            args=(target_port, decoy, server_ready, bad_cert, bad_key),
            daemon=True,
        )
        server_thread.start()
        assert server_ready.wait(timeout=2.0), "Alternate-certificate server did not become ready"

        try:
            subprocess.run([PAYLOAD_PATH], capture_output=True, text=True, timeout=15.0)
        except subprocess.TimeoutExpired:
            pytest.fail("Payload timed out while handling a server with an unpinned certificate")

        server_thread.join(timeout=2.0)

    if os.path.exists(LOOT_PATH):
        with open(LOOT_PATH, "r") as f:
            contents = f.read()
        assert contents != decoy, "Payload accepted data from a TLS server with an unpinned certificate"


def test_payload_functional_execution():
    """
    Functional Verification:
    Spins up a mock server on a random port in [8440, 8450], runs the payload,
    and checks if the exact secret was written to loot.txt.
    """
    assert os.path.isfile(PAYLOAD_PATH), f"Payload binary not found at {PAYLOAD_PATH}"
    assert os.access(PAYLOAD_PATH, os.X_OK), f"Payload binary at {PAYLOAD_PATH} is not executable"

    # Clean up previous loot if it exists
    if os.path.exists(LOOT_PATH):
        os.remove(LOOT_PATH)

    # Pick a random port in the target range
    target_port = random.randint(8440, 8450)
    secret_flag = f"FLAG{{dynamic_test_flag_{random.randint(1000, 9999)}}}"

    server_ready = threading.Event()
    server_thread = threading.Thread(target=mock_tls_server, args=(target_port, secret_flag, server_ready))
    server_thread.daemon = True
    server_thread.start()

    # Wait for the server to bind and listen
    server_ready.wait(timeout=2.0)

    # Execute the payload
    try:
        result = subprocess.run(
            [PAYLOAD_PATH],
            capture_output=True,
            text=True,
            timeout=15.0
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Payload execution timed out after 15 seconds. It may be hanging or scanning incorrectly.")

    # Wait for the server thread to finish sending data
    server_thread.join(timeout=2.0)

    # Verify the loot file
    assert os.path.isfile(LOOT_PATH), f"Payload failed to create {LOOT_PATH}"

    with open(LOOT_PATH, 'r') as f:
        loot_contents = f.read()

    assert loot_contents == secret_flag, (
        f"Loot contents do not match the expected secret.\n"
        f"Expected: {secret_flag}\n"
        f"Got: {loot_contents}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
