#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import sys
import struct
import random
import string
import subprocess
import time
import signal
import uuid
import pytest

ORACLE_PATH = "/tests/parse_single_oracle.py"
AGENT_PATH = "/home/user/parse_single.py"
WATCHER_PATH = "/home/user/watcher.py"
INCOMING = "/home/user/incoming"
PROCESSED = "/home/user/processed"

def generate_fuzz_input(seed: int) -> bytes:
    random.seed(seed)
    length = random.randint(1024, 1024 * 100)
    num_records = random.randint(0, 50)
    data = bytearray(os.urandom(length))
    insert_positions = sorted([random.randint(0, length - 1) for _ in range(num_records)])
    records = []
    for _ in range(num_records):
        payload_len = random.randint(1, 1000)
        chars = string.ascii_letters + string.digits + " \n\t"
        payload = "".join(random.choices(chars, k=payload_len))
        if random.random() < 0.5:
            insert_idx = random.randint(0, len(payload))
            payload = payload[:insert_idx] + "DRAFT" + payload[insert_idx:]
        if random.random() < 0.5:
            payload += "   \t \n"
        payload_bytes = payload.encode("utf-8")
        records.append(b"DOC_BETA_99" + struct.pack("<I", len(payload_bytes)) + payload_bytes)

    result = bytearray()
    last_pos = 0
    for pos, record in zip(insert_positions, records):
        if pos > last_pos:
            result.extend(data[last_pos:pos])
        result.extend(record)
        last_pos = pos
    if last_pos < len(data):
        result.extend(data[last_pos:])
    return bytes(result)

def oracle_output(data: bytes) -> bytes:
    proc = subprocess.run([sys.executable, ORACLE_PATH], input=data, capture_output=True, timeout=20)
    assert proc.returncode == 0, proc.stderr.decode(errors="replace")
    return proc.stdout

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), "parse_single.py is not executable"
    assert open(AGENT_PATH, "rb").read() != open(ORACLE_PATH, "rb").read(), "Submission is byte-identical to the reference implementation"

    for i in range(100):
        input_data = generate_fuzz_input(seed=i)
        oracle_proc = subprocess.run([sys.executable, ORACLE_PATH], input=input_data, capture_output=True)
        agent_proc = subprocess.run([sys.executable, AGENT_PATH], input=input_data, capture_output=True)
        assert agent_proc.returncode == 0, f"Agent script failed on seed {i} with stderr: {agent_proc.stderr.decode(errors='replace')}"
        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f"Mismatch on seed {i}.\n"
                f"Oracle output length: {len(oracle_proc.stdout)}\n"
                f"Agent output length: {len(agent_proc.stdout)}\n"
                f"Oracle output start: {oracle_proc.stdout[:200]!r}\n"
                f"Agent output start: {agent_proc.stdout[:200]!r}"
            )

def kill_existing_watchers():
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            cmdline = open(f"/proc/{entry}/cmdline", "rb").read()
            if WATCHER_PATH.encode() in cmdline:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)

def watcher_has_atomic_publish():
    source = open(WATCHER_PATH, "r", encoding="utf-8").read()
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Attribute) and func.attr in {"replace", "rename", "move"}:
            return True
        if isinstance(func, ast.Name) and func.id in {"replace", "rename"}:
            return True
        if node.args:
            try:
                value = ast.literal_eval(node.args[0])
            except Exception:
                value = None
            if value == "mv" or (isinstance(value, (list, tuple)) and value and value[0] == "mv"):
                return True
    return False

def wait_for_exact(path, expected, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(path, "rb") as f:
                if f.read() == expected:
                    return
        except FileNotFoundError:
            pass
        time.sleep(0.03)
    pytest.fail(f"Timed out waiting for correct output at {path}")

def test_watcher_end_to_end_and_atomic_write():
    assert os.path.isfile(WATCHER_PATH), "watcher.py is missing"
    assert os.path.isdir(INCOMING), "/home/user/incoming directory is missing"
    assert os.path.isdir(PROCESSED), "/home/user/processed directory is missing"
    assert watcher_has_atomic_publish(), "watcher.py does not use an atomic rename/replace/move to publish output"

    kill_existing_watchers()
    token = "verify_" + uuid.uuid4().hex
    first_name = token + ".bin"
    first_input = os.path.join(INCOMING, first_name)
    first_target = os.path.join(PROCESSED, token + ".txt")
    latest = os.path.join(PROCESSED, "latest.txt")
    sentinel = b"PREEXISTING-COMPLETE-FILE"

    payload = (b"chunk DRAFT value " * 180000) + b"   \t\n"
    data = b"ignored-prefix" + b"DOC_BETA_99" + struct.pack("<I", len(payload)) + payload + b"ignored-suffix"
    expected = oracle_output(data)

    with open(first_target, "wb") as f:
        f.write(sentinel)
    try:
        os.unlink(latest)
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(
        [sys.executable, WATCHER_PATH],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        time.sleep(0.5)
        staging = os.path.join(INCOMING, "." + first_name + ".upload")
        with open(staging, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(staging, first_input)

        deadline = time.time() + 25
        observed_bad_state = None
        while time.time() < deadline:
            try:
                size = os.path.getsize(first_target)
                if size not in (len(sentinel), len(expected)):
                    observed_bad_state = size
                    break
                if size == len(expected):
                    with open(first_target, "rb") as f:
                        if f.read() == expected:
                            break
            except FileNotFoundError:
                observed_bad_state = "missing"
                break
            time.sleep(0.001)
        else:
            pytest.fail("Watcher did not produce the first output in time")
        assert observed_bad_state is None, f"Output was exposed in a non-atomic intermediate state: {observed_bad_state}"
        wait_for_exact(first_target, expected)
        assert os.path.islink(latest), "latest.txt is not a symbolic link"
        assert os.path.realpath(latest) == os.path.realpath(first_target), "latest.txt does not point to the newly processed file"

        ignored = os.path.join(INCOMING, token + "_ignored.dat")
        with open(ignored, "wb") as f:
            f.write(data)
        time.sleep(1.0)
        assert not os.path.exists(os.path.join(PROCESSED, token + "_ignored.txt")), "Watcher processed a non-.bin file"

        second_base = token + "_second"
        second_input = os.path.join(INCOMING, second_base + ".bin")
        second_target = os.path.join(PROCESSED, second_base + ".txt")
        payload2 = "second DRAFT record   \n".encode("utf-8")
        data2 = b"DOC_BETA_99" + struct.pack("<I", len(payload2)) + payload2
        expected2 = oracle_output(data2)
        with open(second_input, "wb") as f:
            f.write(data2)
        wait_for_exact(second_target, expected2)
        assert os.path.islink(latest), "latest.txt stopped being a symbolic link"
        assert os.path.realpath(latest) == os.path.realpath(second_target), "latest.txt was not updated for the next file"
    finally:
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
        kill_existing_watchers()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
