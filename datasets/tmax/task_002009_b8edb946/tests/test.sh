#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import select
import string
import struct
import subprocess
import threading
import pytest

AGENT_BIN = "/home/user/barc2tar/target/release/barc2tar"
ORACLE_BIN = "/tests/oracle_barc2tar"

def generate_valid_barc(num_entries):
    data = bytearray(b"BARC")
    data.extend(struct.pack("<I", num_entries))

    for _ in range(num_entries):
        name_len = random.randint(1, 31)
        name = "".join(random.choices(string.ascii_letters + string.digits + "._-", k=name_len)).encode("ascii")
        name_padded = name.ljust(32, b"\x00")

        file_size = random.randint(0, 10000)
        file_data = bytearray(random.getrandbits(8) for _ in range(file_size))

        data.extend(name_padded)
        data.extend(struct.pack("<Q", file_size))
        data.extend(file_data)

    return bytes(data)

def generate_invalid_barc():
    kind = random.choice(["truncated_header", "bad_magic", "truncated_data", "non_ascii_name"])

    if kind == "truncated_header":
        return b"BAR"
    elif kind == "bad_magic":
        data = bytearray(b"CRAZ")
        data.extend(struct.pack("<I", 1))
        data.extend(b"test".ljust(32, b"\x00"))
        data.extend(struct.pack("<Q", 5))
        data.extend(b"12345")
        return bytes(data)
    elif kind == "truncated_data":
        data = bytearray(b"BARC")
        data.extend(struct.pack("<I", 1))
        data.extend(b"test".ljust(32, b"\x00"))
        data.extend(struct.pack("<Q", 100))
        data.extend(b"12345")
        return bytes(data)
    elif kind == "non_ascii_name":
        data = bytearray(b"BARC")
        data.extend(struct.pack("<I", 1))
        bad_name = b"\xff\xfe\xfd\xfc".ljust(32, b"\x00")
        data.extend(bad_name)
        data.extend(struct.pack("<Q", 5))
        data.extend(b"12345")
        return bytes(data)
    return b""

def run_binary(binary_path, input_data):
    try:
        result = subprocess.run(
            [binary_path],
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2.0
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return None, b"", b"Timeout"

def test_barc2tar_equivalence():
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"

    assert os.path.isfile(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary at {ORACLE_BIN} is not executable"

    random.seed(42)

    num_tests = 500
    for i in range(num_tests):
        if random.random() < 0.8:
            num_entries = random.randint(0, 20)
            input_data = generate_valid_barc(num_entries)
        else:
            input_data = generate_invalid_barc()

        oracle_code, oracle_out, oracle_err = run_binary(ORACLE_BIN, input_data)
        agent_code, agent_out, agent_err = run_binary(AGENT_BIN, input_data)

        assert agent_code is not None, f"Agent binary timed out on test {i}"
        assert agent_code == oracle_code, f"Exit code mismatch on test {i}: oracle={oracle_code}, agent={agent_code}"
        assert agent_out == oracle_out, f"Stdout mismatch on test {i}"

        oracle_has_err = len(oracle_err) > 0
        agent_has_err = len(agent_err) > 0
        assert agent_has_err == oracle_has_err, f"Stderr presence mismatch on test {i}: oracle_has_err={oracle_has_err}, agent_has_err={agent_has_err}"

def read_rss_kb(pid):
    try:
        with open(f"/proc/{pid}/status", "r", encoding="ascii") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError):
        pass
    return 0

def test_large_file_is_streamed():
    file_size = 64 * 1024 * 1024
    initial_size = 1024 * 1024
    chunk = b"\x5a" * (256 * 1024)
    header = b"BARC" + struct.pack("<I", 1)
    header += b"large.bin".ljust(32, b"\x00")
    header += struct.pack("<Q", file_size)

    proc = subprocess.Popen(
        [AGENT_BIN],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )
    drain_thread = None
    try:
        proc.stdin.write(header)
        remaining_initial = initial_size
        while remaining_initial:
            part = chunk[:min(len(chunk), remaining_initial)]
            proc.stdin.write(part)
            remaining_initial -= len(part)

        ready, _, _ = select.select([proc.stdout], [], [], 3.0)
        assert ready, "Converter produced no output until the complete large file was buffered"
        first = os.read(proc.stdout.fileno(), 65536)
        assert first, "Converter closed stdout before producing a tar archive"

        total_output = [len(first)]
        drain_errors = []

        def drain_stdout():
            try:
                while True:
                    block = os.read(proc.stdout.fileno(), 1024 * 1024)
                    if not block:
                        break
                    total_output[0] += len(block)
            except BaseException as exc:
                drain_errors.append(exc)

        drain_thread = threading.Thread(target=drain_stdout, daemon=True)
        drain_thread.start()

        baseline_rss = read_rss_kb(proc.pid)
        max_rss = baseline_rss
        remaining = file_size - initial_size
        while remaining:
            part = chunk[:min(len(chunk), remaining)]
            proc.stdin.write(part)
            remaining -= len(part)
            max_rss = max(max_rss, read_rss_kb(proc.pid))

        proc.stdin.close()
        proc.stdin = None
        returncode = proc.wait(timeout=20.0)
        drain_thread.join(timeout=5.0)
        stderr = proc.stderr.read()

        assert not drain_thread.is_alive(), "Timed out draining converter output"
        assert not drain_errors, f"Failed while reading converter output: {drain_errors[0]}"
        assert returncode == 0, f"Large valid archive failed with code {returncode}: {stderr!r}"
        assert total_output[0] >= file_size + 512, "Large-file tar output was unexpectedly short"
        assert max_rss - baseline_rss < 32 * 1024, (
            f"Memory usage grew by {max_rss - baseline_rss} KiB while processing a large file; "
            "the payload appears to have been buffered instead of streamed"
        )
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if drain_thread is not None and drain_thread.is_alive():
            drain_thread.join(timeout=1.0)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
