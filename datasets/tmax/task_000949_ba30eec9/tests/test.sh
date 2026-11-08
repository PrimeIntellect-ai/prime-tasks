#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import http.server
import os
import secrets
import signal
import socket
import socketserver
import subprocess
import threading
import time

import pytest

CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
FILTER_SRC = "/home/user/filter.go"
FILTER_BIN = "/home/user/filter"
PIPELINE_SCRIPT = "/home/user/pipeline.sh"
BUILT_FILTER = "/tmp/filter-from-source"


def run_filter(path, data):
    result = subprocess.run([path], input=data, capture_output=True, timeout=5)
    assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
    return result.stdout


def test_filter_binary_exists():
    assert os.path.isfile(FILTER_BIN), f"{FILTER_BIN} does not exist. Did you compile your Go code?"
    assert os.access(FILTER_BIN, os.X_OK), f"{FILTER_BIN} is not executable."
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{FILTER_BIN} is not a compiled executable."
    info = subprocess.run(["go", "version", "-m", FILTER_BIN], capture_output=True, text=True, timeout=5)
    assert info.returncode == 0 and "go1." in info.stdout, f"{FILTER_BIN} is not a Go executable."


def test_filter_source_builds():
    assert os.path.isfile(FILTER_SRC), f"{FILTER_SRC} does not exist."
    result = subprocess.run(["go", "build", "-o", BUILT_FILTER, FILTER_SRC], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(BUILT_FILTER) and os.access(BUILT_FILTER, os.X_OK)


def test_pipeline_script_exists():
    assert os.path.isfile(PIPELINE_SCRIPT), f"{PIPELINE_SCRIPT} does not exist."
    assert os.access(PIPELINE_SCRIPT, os.X_OK), f"{PIPELINE_SCRIPT} is not executable."


def test_clean_corpus():
    if not os.path.isdir(CLEAN_DIR):
        pytest.skip(f"Clean corpus directory {CLEAN_DIR} not found.")

    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]
    modified = []

    for cf in clean_files:
        path = os.path.join(CLEAN_DIR, cf)
        with open(path, 'rb') as f:
            input_data = f.read()

        try:
            result = subprocess.run([FILTER_BIN], input=input_data, capture_output=True, timeout=5)
            input_lines = [line.strip() for line in input_data.decode('utf-8').splitlines() if line.strip()]
            output_lines = [line.strip() for line in result.stdout.decode('utf-8').splitlines() if line.strip()]
            if input_lines != output_lines:
                modified.append(cf)
        except Exception:
            modified.append(cf)

    assert not modified, f"{len(modified)} of {len(clean_files)} clean modified: {modified}"


def test_evil_corpus():
    if not os.path.isdir(EVIL_DIR):
        pytest.skip(f"Evil corpus directory {EVIL_DIR} not found.")

    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]
    bypassed = []

    for ef in evil_files:
        path = os.path.join(EVIL_DIR, ef)
        with open(path, 'rb') as f:
            input_data = f.read()

        try:
            result = subprocess.run([FILTER_BIN], input=input_data, capture_output=True, timeout=5)
            output_lines = [line.strip() for line in result.stdout.decode('utf-8').splitlines() if line.strip()]
            if output_lines:
                bypassed.append(ef)
        except Exception:
            bypassed.append(ef)

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed: {bypassed}"


def test_filter_semantics():
    assert os.path.isfile(BUILT_FILTER), "filter.go was not successfully compiled"
    base = 1_700_000_000 + secrets.randbelow(100_000_000)
    tag = secrets.token_hex(5)
    accepted1 = f'"tx,{tag}",{base},userA,001.50,Food9\n'.encode()
    accepted2 = f'{tag}b,{base + 1},userB,0,Cat2\n'.encode()
    accepted3 = f'{tag}c,{base + 2},userC,3.25,Z9\n'.encode()
    data = b"".join([
        accepted1,
        f'{tag}eq,{base},user,4,Okay\n'.encode(),
        f'{tag}low,{base - 1},user,4,Okay\n'.encode(),
        f'{tag}amt,{base + 100},user,not-a-float,Okay\n'.encode(),
        accepted2,
        f'{tag}neg,{base + 2},user,-0.01,Okay\n'.encode(),
        f'{tag}cat,{base + 2},user,4,bad-cat\n'.encode(),
        f'{tag}short,{base + 2},user,4\n'.encode(),
        f'{tag}long,{base + 2},user,4,Okay,extra\n'.encode(),
        f'{tag}time,nope,user,4,Okay\n'.encode(),
        accepted3,
    ])
    expected = accepted1 + accepted2 + accepted3

    evil_only = b"".join([
        f'{tag},bad,user,1,Good\n'.encode(),
        f'{tag},{base},user,-2,Good\n'.encode(),
        f'{tag},{base},user,2,Bad!\n'.encode(),
        f'{tag},{base},user,2\n'.encode(),
    ])
    clean_reset = f'{tag},{base - 500},user9,8.75,ABC123\n'.encode()

    for binary in (FILTER_BIN, BUILT_FILTER):
        assert run_filter(binary, data) == expected
        assert run_filter(binary, evil_only) == b""
        assert run_filter(binary, clean_reset) == clean_reset


def stop_packaged_services():
    me = os.getpid()
    for proc in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            pid = int(proc.split("/")[2])
            if pid == me:
                continue
            cmdline = open(proc, "rb").read()
            if b"/app/producer.py" in cmdline or b"/app/consumer.py" in cmdline:
                os.kill(pid, signal.SIGTERM)
        except (OSError, ValueError):
            pass
    time.sleep(0.5)


def test_pipeline_end_to_end():
    stop_packaged_services()
    base = 1_800_000_000 + secrets.randbelow(100_000_000)
    tag = secrets.token_hex(6)
    good1 = f'{tag}a,{base},user1,10.5,Food1\n'.encode()
    good2 = f'{tag}b,{base + 1},user2,0,Cat9\n'.encode()
    body = b"".join([
        good1,
        f'{tag}old,{base},user3,4,Good\n'.encode(),
        f'{tag}bad,{base + 1},user4,4,bad-cat\n'.encode(),
        good2,
    ])
    expected = good1 + good2
    requested = []
    received = bytearray()
    receiver_done = threading.Event()

    class ReusableHTTPServer(http.server.ThreadingHTTPServer):
        allow_reuse_address = True

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            requested.append(self.path)
            if self.path != "/data":
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/csv")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()

        def log_message(self, *args):
            pass

    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    class Sink(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(4)
            try:
                while True:
                    chunk = self.request.recv(4096)
                    if not chunk:
                        break
                    received.extend(chunk)
            except socket.timeout:
                pass
            finally:
                receiver_done.set()

    httpd = ReusableHTTPServer(("127.0.0.1", 5000), Handler)
    sink = ReusableTCPServer(("127.0.0.1", 5001), Sink)
    http_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    sink_thread = threading.Thread(target=sink.handle_request, daemon=True)
    http_thread.start()
    sink_thread.start()

    real_filter = FILTER_BIN + ".real-verifier"
    marker = f"/tmp/filter-invoked-{secrets.token_hex(8)}"
    proc = None
    os.rename(FILTER_BIN, real_filter)
    try:
        with open(FILTER_BIN, "w") as f:
            f.write(f'#!/bin/sh\nprintf x >> "{marker}"\nexec "{real_filter}" "$@"\n')
        os.chmod(FILTER_BIN, 0o755)
        proc = subprocess.Popen(
            [PIPELINE_SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True
        )
        deadline = time.time() + 8
        while time.time() < deadline and not receiver_done.is_set():
            time.sleep(0.05)
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()
        receiver_done.wait(2)
    finally:
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        if os.path.exists(FILTER_BIN):
            os.unlink(FILTER_BIN)
        os.rename(real_filter, FILTER_BIN)
        httpd.shutdown()
        httpd.server_close()
        sink.server_close()

    assert requested and requested[0] == "/data", "pipeline did not request the producer /data endpoint"
    assert os.path.exists(marker) and os.path.getsize(marker) > 0, "pipeline did not invoke /home/user/filter"
    assert bytes(received) == expected, f"consumer received {bytes(received)!r}, expected {expected!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
