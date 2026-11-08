#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import socket
import struct
import subprocess
import tempfile
import threading
import pytest


def test_deploy_port_file():
    """Check that the deploy port file contains the correct port."""
    port_file = "/home/user/deploy_port.txt"
    assert os.path.isfile(port_file), f"Missing {port_file}"
    with open(port_file, "r") as f:
        content = f.read().strip()
    assert content == "9002", f"Expected port 9002 in {port_file}, but got {content}"


def test_ssh_tunnel_active():
    """Check that an SSH process really forwards local port 8080 to localhost:9002."""
    ssh_tunnel_found = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if not args or os.path.basename(args[0]) != "ssh":
            continue
        command = " ".join(args)
        if "8080:" in command and ":9002" in command:
            ssh_tunnel_found = True
            break
    assert ssh_tunnel_found, "No SSH process configured to forward local port 8080 to port 9002 was found"

    request = secrets.token_bytes(32)
    response = secrets.token_bytes(37)
    server_errors = []
    ready = threading.Event()

    def backend():
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", 9002))
            listener.listen(1)
            listener.settimeout(5)
            ready.set()
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(5)
                received = b""
                while len(received) < len(request):
                    part = conn.recv(len(request) - len(received))
                    if not part:
                        break
                    received += part
                if received != request:
                    raise AssertionError("Backend did not receive data sent through port 8080")
                conn.sendall(response)
        except BaseException as exc:
            server_errors.append(exc)
            ready.set()
        finally:
            listener.close()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert ready.wait(2), "Backend test listener did not start"
    if server_errors:
        raise server_errors[0]

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    try:
        s.connect(("127.0.0.1", 8080))
        s.sendall(request)
        received = b""
        while len(received) < len(response):
            part = s.recv(len(response) - len(received))
            if not part:
                break
            received += part
        assert received == response, "Port 8080 did not forward traffic to localhost:9002"
    except ConnectionRefusedError:
        pytest.fail("SSH tunnel is not listening on local port 8080.")
    finally:
        s.close()

    thread.join(6)
    assert not thread.is_alive(), "Forwarding test timed out"
    if server_errors:
        raise server_errors[0]


def test_worker_wrapper():
    """Check that the worker wrapper sets the correct ulimit and executes arguments."""
    wrapper_path = "/home/user/worker_wrapper.sh"
    assert os.path.isfile(wrapper_path), f"Missing {wrapper_path}"
    assert os.access(wrapper_path, os.X_OK), f"{wrapper_path} is not executable"

    try:
        result = subprocess.run(
            [wrapper_path, "sh", "-c", "ulimit -f"],
            capture_output=True,
            text=True,
            timeout=5
        )
        output = result.stdout.strip()
        assert "51200" in output, f"Expected ulimit -f to be 51200, but got: {output}"
    except Exception as e:
        pytest.fail(f"Failed to execute worker wrapper: {e}")


def test_validator_clean_corpus():
    """Check that the validator accepts all clean files."""
    validator_path = "/home/user/validator"
    clean_dir = "/app/corpus/clean/"

    assert os.path.isfile(validator_path), f"Missing validator executable at {validator_path}"
    assert os.access(validator_path, os.X_OK), f"Validator at {validator_path} is not executable"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    failed_files = []

    for filepath in clean_files:
        result = subprocess.run([validator_path, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected: {', '.join(failed_files)}")


def test_validator_evil_corpus():
    """Check that the validator rejects all evil files."""
    validator_path = "/home/user/validator"
    evil_dir = "/app/corpus/evil/"

    assert os.path.isfile(validator_path), f"Missing validator executable at {validator_path}"
    assert os.access(validator_path, os.X_OK), f"Validator at {validator_path} is not executable"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    failed_files = []

    for filepath in evil_files:
        result = subprocess.run([validator_path, filepath], capture_output=True)
        if result.returncode == 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed: {', '.join(failed_files)}")


def wav_chunk(kind, payload):
    result = kind + struct.pack("<I", len(payload)) + payload
    if len(payload) & 1:
        result += b"\0"
    return result


def make_wave(chunks):
    body = b"WAVE" + b"".join(chunks)
    return b"RIFF" + struct.pack("<I", len(body)) + body


def test_validator_generated_adversarial_files():
    """Compile the submitted source and exercise both artifacts on unpredictable paths."""
    source = "/home/user/validator.cpp"
    validator = "/home/user/validator"
    assert os.path.isfile(source), f"Missing validator source at {source}"
    assert os.path.isfile(validator), f"Missing validator executable at {validator}"
    assert os.access(validator, os.X_OK), f"Validator at {validator} is not executable"

    fmt = struct.pack("<HHIIHH", 1, 1, 44100, 88200, 2, 16)

    with tempfile.TemporaryDirectory(prefix="wavcheck_" + secrets.token_hex(6) + "_") as directory:
        rebuilt = os.path.join(directory, secrets.token_hex(10))
        compiled = subprocess.run(
            ["g++", "-std=c++17", source, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compiled.returncode == 0, f"validator.cpp did not compile:\n{compiled.stderr}"

        valid_blobs = [
            make_wave([wav_chunk(b"fmt ", fmt), wav_chunk(b"data", secrets.token_bytes(64))]),
            make_wave([wav_chunk(b"JUNK", secrets.token_bytes(7)), wav_chunk(b"fmt ", fmt), wav_chunk(b"data", secrets.token_bytes(18))]),
            make_wave([wav_chunk(b"fmt ", fmt), wav_chunk(b"LIST", b""), wav_chunk(b"data", b"")]),
        ]

        oversized_data = (
            b"RIFF" + struct.pack("<I", 100000037) + b"WAVE" +
            wav_chunk(b"fmt ", fmt) + b"data" + struct.pack("<I", 100000001)
        )
        oversized_unknown = (
            b"RIFF" + struct.pack("<I", 100000013) + b"WAVE" +
            b"ABCD" + struct.pack("<I", 100000001)
        )
        invalid_blobs = [
            b"NOTR" + struct.pack("<I", 4) + b"WAVE",
            b"RIFF" + struct.pack("<I", 4) + b"NOPE",
            make_wave([wav_chunk(b"fmt ", fmt)]) + b"data\x04\x00",
            b"RIFF" + struct.pack("<I", 34) + b"WAVE" + wav_chunk(b"fmt ", fmt) + b"data" + struct.pack("<I", 20) + b"\0\0",
            oversized_data,
            oversized_unknown,
        ]

        cases = []
        for expected, blobs in ((0, valid_blobs), (1, invalid_blobs)):
            for blob in blobs:
                path = os.path.join(directory, secrets.token_hex(16) + ".bin")
                with open(path, "wb") as f:
                    f.write(blob)
                cases.append((path, expected))

        for artifact in (validator, rebuilt):
            shuffled = list(cases)
            random.SystemRandom().shuffle(shuffled)
            for path, expected in shuffled:
                result = subprocess.run([artifact, path], capture_output=True, timeout=5)
                if expected == 0:
                    assert result.returncode == 0, f"{artifact} rejected a generated valid RIFF/WAVE file"
                else:
                    assert result.returncode != 0, f"{artifact} accepted a generated malformed or oversized RIFF/WAVE file"

            assert subprocess.run([artifact], capture_output=True, timeout=5).returncode != 0, "Validator accepted zero arguments"
            assert subprocess.run([artifact, cases[0][0], cases[1][0]], capture_output=True, timeout=5).returncode != 0, "Validator accepted more than one argument"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
