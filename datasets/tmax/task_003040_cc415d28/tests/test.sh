#!/bin/bash
set -e
mkdir -p /logs/verifier

# Use controlled listeners for the end-to-end test rather than any services left running.
pkill -x log_filter 2>/dev/null || true
pkill -f '[d]ashboard.py' 2>/dev/null || true
sleep 0.2

cleanup() {
    pkill -x log_filter 2>/dev/null || true
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import subprocess
import tempfile
import threading
import time

EXECUTABLE = "/home/user/workspace/log_filter"
SOURCE = "/home/user/workspace/log_filter.c"


def test_executable_exists():
    executable = EXECUTABLE
    assert os.path.isfile(executable), f"Executable missing: {executable}"
    assert os.access(executable, os.X_OK), f"File is not executable: {executable}"
    assert os.path.isfile(SOURCE), f"C source missing: {SOURCE}"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_filter is not a compiled ELF executable"


def test_adversarial_corpus():
    executable = EXECUTABLE
    evil_dir = "/home/user/hidden_corpus/evil/"
    clean_dir = "/home/user/hidden_corpus/clean/"

    evil_bypassed = []
    evil_total = 0
    if os.path.isdir(evil_dir):
        for filename in os.listdir(evil_dir):
            filepath = os.path.join(evil_dir, filename)
            if not os.path.isfile(filepath):
                continue
            evil_total += 1
            with tempfile.NamedTemporaryFile() as out_f:
                result = subprocess.run([executable, "--test", filepath, out_f.name], capture_output=True)
                assert result.returncode == 0, f"Filter crashed on evil file {filename}"
                out_f.seek(0)
                output = out_f.read()
                if len(output.strip()) > 0:
                    evil_bypassed.append(filename)

    clean_modified = []
    clean_total = 0
    if os.path.isdir(clean_dir):
        for filename in os.listdir(clean_dir):
            filepath = os.path.join(clean_dir, filename)
            if not os.path.isfile(filepath):
                continue
            clean_total += 1
            with tempfile.NamedTemporaryFile() as out_f:
                result = subprocess.run([executable, "--test", filepath, out_f.name], capture_output=True)
                assert result.returncode == 0, f"Filter crashed on clean file {filename}"
                out_f.seek(0)
                output = out_f.read()
                with open(filepath, 'rb') as in_f:
                    expected = in_f.read()
                if output != expected:
                    clean_modified.append(filename)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {evil_total} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {clean_total} clean modified: {', '.join(clean_modified)}")

    assert not error_msgs, " | ".join(error_msgs)


def test_generated_bulk_corpus():
    marker = secrets.token_hex(12).encode("ascii")
    clean = [
        b"Jan 1 12:00:00 host sshd: Accepted publickey for " + marker + b"\n",
        b"Feb 28 03:04:05 web nginx: request completed " + marker + b"\n",
    ]
    prefix = b"Mar 3 09:08:07 host app: "
    evil = [
        prefix + b"attempt | command " + marker + b"\n",
        prefix + b"attempt > file " + marker + b"\n",
        prefix + b"attempt < file " + marker + b"\n",
        prefix + b"attempt & command " + marker + b"\n",
        prefix + b"attempt ; command " + marker + b"\n",
        prefix + b"attempt $ variable " + marker + b"\n",
        prefix + b"control\x01character " + marker + b"\n",
        prefix + b"tab\tcharacter " + marker + b"\n",
        prefix + (b"A" * 101) + b"\n",
        b"not a syslog record " + marker + b"\n",
    ]
    records = [clean[0], evil[0], evil[6], clean[1]] + evil[1:6] + evil[7:]

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.log")
        output_path = os.path.join(td, "output.log")
        with open(input_path, "wb") as f:
            f.write(b"".join(records))
        result = subprocess.run(
            [EXECUTABLE, "--test", input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
        assert os.path.isfile(output_path), "Bulk mode did not create its output file"
        with open(output_path, "rb") as f:
            actual = f.read()
        assert actual == b"".join(clean), f"Unexpected bulk-filter output: {actual!r}"


def test_udp_to_tcp_daemon_flow():
    marker = secrets.token_hex(12).encode("ascii")
    clean_one = b"Apr 4 10:11:12 vm kernel: boot complete " + marker + b"\n"
    clean_two = b"May 5 13:14:15 vm service: health check ok " + marker + b"\n"
    evil_meta = b"Apr 4 10:11:13 vm kernel: injected ; command " + marker + b"\n"
    evil_long = b"Apr 4 10:11:14 vm kernel: " + (b"Z" * 101) + b"\n"

    received = bytearray()
    stop = threading.Event()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 8080))
    server.listen(8)
    server.settimeout(0.2)

    def collect():
        while not stop.is_set():
            try:
                conn, _ = server.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with conn:
                conn.settimeout(0.2)
                while True:
                    try:
                        chunk = conn.recv(4096)
                    except socket.timeout:
                        if stop.is_set():
                            break
                        continue
                    if not chunk:
                        break
                    received.extend(chunk)

    thread = threading.Thread(target=collect, daemon=True)
    thread.start()
    proc = subprocess.Popen(
        [EXECUTABLE],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        time.sleep(0.5)
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            # Repeat to tolerate normal daemon startup scheduling; content checks do not
            # depend on receiving an exact number of copies.
            for _ in range(3):
                for record in (clean_one, evil_meta, clean_two, evil_long):
                    udp.sendto(record, ("127.0.0.1", 5000))
                time.sleep(0.1)
        finally:
            udp.close()

        deadline = time.time() + 4
        while time.time() < deadline:
            data = bytes(received)
            if clean_one in data and clean_two in data:
                break
            time.sleep(0.05)

        data = bytes(received)
        assert clean_one in data, f"First clean UDP log was not forwarded over TCP: {data!r}"
        assert clean_two in data, f"Second clean UDP log was not forwarded over TCP: {data!r}"
        assert evil_meta not in data, "Shell-metacharacter log reached the dashboard"
        assert evil_long not in data, "Overlong-word log reached the dashboard"
    finally:
        stop.set()
        server.close()
        thread.join(timeout=1)
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
