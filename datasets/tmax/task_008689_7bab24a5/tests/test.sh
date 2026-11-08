#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import struct
import subprocess
import tempfile
import time
import uuid

import pytest

BEACON = "/home/user/beacon"
SOURCE = "/home/user/beacon.c"
TEST_SCRIPT = "/home/user/test_beacon.py"
PROOF = "/home/user/proof.txt"
EXACT_COMMAND = b'echo "SPACE TEST" > /home/user/proof.txt'


def stop_process(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=2)


def start_beacon(path):
    proc = subprocess.Popen(
        [path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(0.5)
    assert proc.poll() is None, f"Beacon {path} exited before accepting UDP traffic."
    return proc


def send_payload(payload):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(payload, ("127.0.0.1", 8888))


def wait_for_file(path, timeout=2.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.isfile(path):
            return True
        time.sleep(0.05)
    return os.path.isfile(path)


def exercise_strict_tlv(beacon_path):
    token = uuid.uuid4().hex
    valid_file = f"/tmp/beacon_valid_{token}"
    bounded_file = f"/tmp/beacon_bounded_{token}"
    trailing_file = f"/tmp/beacon_trailing_{token}"
    truncated_file = f"/tmp/beacon_truncated_{token}"
    paths = [valid_file, bounded_file, trailing_file, truncated_file]

    for path in paths:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    proc = start_beacon(beacon_path)
    try:
        # A verifier-generated command containing spaces must execute.
        valid_cmd = f"echo {token} SPACE TEST > {valid_file}".encode()
        send_payload(b"\x02" + struct.pack("<H", len(valid_cmd)) + valid_cmd)
        assert wait_for_file(valid_file), "A valid Exec TLV containing spaces was not executed."
        with open(valid_file, "r") as f:
            assert f.read().strip() == f"{token} SPACE TEST"

        # Bytes after the declared Value length must not become part of the command.
        bounded_cmd = f"echo BOUNDED > {bounded_file}".encode()
        trailing = f"; echo TRAILING > {trailing_file}".encode()
        send_payload(b"\x02" + struct.pack("<H", len(bounded_cmd)) + bounded_cmd + trailing)
        assert wait_for_file(bounded_file), "The command within the declared TLV length was not executed."
        time.sleep(0.4)
        assert not os.path.exists(trailing_file), "Bytes beyond the TLV length were executed."

        # A datagram shorter than its declared length must be ignored.
        truncated_cmd = f"echo TRUNCATED > {truncated_file}".encode()
        send_payload(b"\x02" + struct.pack("<H", len(truncated_cmd) + 7) + truncated_cmd)
        time.sleep(0.5)
        assert not os.path.exists(truncated_file), "A truncated TLV payload was executed."
        assert proc.poll() is None, "Beacon terminated while processing TLV inputs."
    finally:
        stop_process(proc)
        for path in paths:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_beacon_compiled():
    assert os.path.isfile(BEACON), f"Compiled binary {BEACON} does not exist."
    assert os.access(BEACON, os.X_OK), f"File {BEACON} is not executable."
    with open(BEACON, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BEACON} is not a compiled ELF binary."


def test_test_script_exists():
    assert os.path.isfile(TEST_SCRIPT), f"Test script {TEST_SCRIPT} does not exist."


def test_regression_script_sends_required_tlv():
    try:
        os.remove(PROOF)
    except FileNotFoundError:
        pass

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as listener:
        listener.bind(("127.0.0.1", 8888))
        listener.settimeout(3)
        result = subprocess.run(
            ["python3", TEST_SCRIPT], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, (
            f"Test script failed with return code {result.returncode}. Error: {result.stderr}"
        )
        try:
            payload, _ = listener.recvfrom(65535)
        except socket.timeout:
            pytest.fail("Regression script did not send a UDP payload to 127.0.0.1:8888.")

    expected = b"\x02" + struct.pack("<H", len(EXACT_COMMAND)) + EXACT_COMMAND
    assert payload == expected, "Regression script did not send the exact required Exec TLV payload."


def test_beacon_functionality():
    if os.path.exists(PROOF):
        os.remove(PROOF)

    beacon_proc = start_beacon(BEACON)
    try:
        result = subprocess.run(
            ["python3", TEST_SCRIPT], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, (
            f"Test script failed with return code {result.returncode}. Error: {result.stderr}"
        )
        assert wait_for_file(PROOF), f"Proof file {PROOF} was not created."
        with open(PROOF, "r") as f:
            content = f.read()
        assert content.strip() == "SPACE TEST", (
            f"Proof file content is incorrect. Expected 'SPACE TEST', got '{content.strip()}'"
        )
    finally:
        stop_process(beacon_proc)


def test_binary_strictly_parses_verifier_generated_tlvs():
    exercise_strict_tlv(BEACON)


def test_fixed_source_builds_and_has_same_behavior():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    fd, rebuilt = tempfile.mkstemp(prefix="rebuilt_beacon_", dir="/tmp")
    os.close(fd)
    os.remove(rebuilt)
    try:
        result = subprocess.run(
            ["gcc", "-O2", SOURCE, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Fixed beacon.c does not compile: {result.stderr}"
        exercise_strict_tlv(rebuilt)
    finally:
        try:
            os.remove(rebuilt)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
