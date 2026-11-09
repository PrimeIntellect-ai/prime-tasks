#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'API_EOF' > /tmp/verifier_api.py
from flask import Flask, request
import os
import redis
import socket

app = Flask(__name__)
r = redis.Redis(host="127.0.0.1", port=6379, db=0)
audit_socket = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
audit_path = os.environ["VERIFIER_AUDIT_SOCKET"]

@app.route('/health', methods=['GET'])
def health():
    return "OK", 200

@app.route('/report', methods=['POST'])
def report():
    data = request.get_json(silent=True)
    if data and 'filename' in data:
        filename = str(data['filename'])
        replacements = data.get('replacements', 0)
        r.set(filename, replacements)
        audit_socket.sendto((filename + "\t" + str(replacements)).encode(), audit_path)
    return "OK", 200
API_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import select
import shutil
import socket
import struct
import subprocess
import threading
import time
import urllib.request

import redis

RAW_DIR = "/home/user/docs_raw"
PROCESSED_DIR = "/home/user/docs_processed"
AUDIT_PATH = "/tmp/verifier_metrics.sock"
PATTERN = re.compile(r'<legacy-ref target="(.*?)">')


class MetricsCollector:
    def __init__(self, path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
        self.sock.bind(path)
        self.sock.settimeout(0.05)
        self.path = path
        self.messages = []
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        while not self.stop_event.is_set():
            try:
                self.messages.append(self.sock.recv(65535).decode())
            except socket.timeout:
                continue
        while True:
            try:
                self.sock.setblocking(False)
                self.messages.append(self.sock.recv(65535).decode())
            except (BlockingIOError, OSError):
                break

    def start(self):
        self.thread.start()

    def stop(self):
        time.sleep(0.05)
        self.stop_event.set()
        self.thread.join(timeout=2)
        self.sock.close()
        try:
            os.unlink(self.path)
        except FileNotFoundError:
            pass


class RenameWatcher:
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_Q_OVERFLOW = 0x00004000

    def __init__(self, directory):
        libc = ctypes.CDLL(None, use_errno=True)
        self._libc = libc
        self.fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "inotify_init1 failed")
        self.wd = libc.inotify_add_watch(
            self.fd,
            os.fsencode(directory),
            self.IN_MOVED_FROM | self.IN_MOVED_TO | self.IN_Q_OVERFLOW,
        )
        if self.wd < 0:
            raise OSError(ctypes.get_errno(), "inotify_add_watch failed")
        self.events = []
        self.overflow = False
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _read_available(self):
        while True:
            try:
                data = os.read(self.fd, 1024 * 1024)
            except BlockingIOError:
                return
            if not data:
                return
            offset = 0
            while offset < len(data):
                wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode(errors="surrogateescape")
                if mask & self.IN_Q_OVERFLOW:
                    self.overflow = True
                if mask & (self.IN_MOVED_FROM | self.IN_MOVED_TO):
                    self.events.append((mask, cookie, name))

    def _run(self):
        while not self.stop_event.is_set():
            ready, _, _ = select.select([self.fd], [], [], 0.05)
            if ready:
                self._read_available()
        self._read_available()

    def start(self):
        self.thread.start()

    def stop(self):
        time.sleep(0.05)
        self.stop_event.set()
        self.thread.join(timeout=2)
        self._read_available()
        os.close(self.fd)


def stop_existing_gunicorn():
    subprocess.run(["pkill", "-9", "gunicorn"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.1)


def ensure_redis():
    client = redis.Redis(host="127.0.0.1", port=6379, db=0)
    try:
        client.ping()
    except redis.ConnectionError:
        subprocess.run(["redis-server", "--daemonize", "yes"], check=True)
        deadline = time.time() + 3
        while True:
            try:
                client.ping()
                break
            except redis.ConnectionError:
                if time.time() >= deadline:
                    raise
                time.sleep(0.05)
    return client


def start_instrumented_api():
    env = os.environ.copy()
    env["VERIFIER_AUDIT_SOCKET"] = AUDIT_PATH
    proc = subprocess.Popen(
        ["gunicorn", "-w", "4", "-b", "127.0.0.1:5000", "--chdir", "/tmp", "verifier_api:app"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError("Instrumented Flask service failed to start")
        try:
            with urllib.request.urlopen("http://127.0.0.1:5000/health", timeout=0.2) as response:
                if response.status == 200:
                    return proc
        except Exception:
            time.sleep(0.05)
    proc.kill()
    raise AssertionError("Instrumented Flask service did not become ready")


def test_processor_performance_and_correctness():
    assert os.path.isfile("/app/processor.py"), "/app/processor.py is missing or is not a regular file"

    raw_files = sorted(f for f in os.listdir(RAW_DIR) if f.endswith(".md"))
    assert len(raw_files) == 10000, f"Expected 10000 raw markdown files, found {len(raw_files)}"

    expected_contents = {}
    expected_counts = {}
    for filename in raw_files:
        with open(os.path.join(RAW_DIR, filename), "r") as handle:
            original = handle.read()
        expected_counts[filename] = len(PATTERN.findall(original))
        expected_contents[filename] = PATTERN.sub(
            lambda match: f"[{match.group(1)}](/docs/{match.group(1)})", original
        )

    if os.path.exists(PROCESSED_DIR):
        shutil.rmtree(PROCESSED_DIR)
    os.makedirs(PROCESSED_DIR, exist_ok=True)

    r = ensure_redis()
    r.flushall()
    stop_existing_gunicorn()

    collector = MetricsCollector(AUDIT_PATH)
    collector.start()
    api_proc = start_instrumented_api()
    watcher = RenameWatcher(PROCESSED_DIR)
    watcher.start()

    try:
        t0 = time.perf_counter()
        proc = subprocess.run(
            ["python", "/app/processor.py"], capture_output=True, text=True
        )
        runtime = time.perf_counter() - t0
    finally:
        watcher.stop()
        collector.stop()
        api_proc.terminate()
        try:
            api_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            api_proc.kill()

    assert proc.returncode == 0, (
        f"Processor script failed with return code {proc.returncode}.\n"
        f"Stdout: {proc.stdout}\nStderr: {proc.stderr}"
    )

    threshold = 3.5
    assert runtime <= threshold, f"Execution too slow: {runtime:.2f}s (Threshold: {threshold}s)"

    keys = r.keys('*')
    assert len(keys) == 10000, f"Expected 10000 metrics in Redis, found {len(keys)}"
    redis_metrics = {key.decode(): int(r.get(key)) for key in keys}
    assert set(redis_metrics) == set(raw_files), "Redis metric filenames do not match the raw documents"
    assert redis_metrics == expected_counts, "Redis replacement counts are incorrect"

    submitted_metrics = {}
    for message in collector.messages:
        filename, separator, value = message.partition("\t")
        assert separator, f"Malformed metric observed from Flask: {message!r}"
        submitted_metrics[filename] = int(value)
    assert set(submitted_metrics) == set(raw_files), "Not all metrics were submitted through the Flask /report endpoint"
    assert submitted_metrics == expected_counts, "Flask received incorrect replacement counts"

    processed_files = os.listdir(PROCESSED_DIR)
    assert len(processed_files) == 10000, f"Expected 10000 processed files, found {len(processed_files)}."
    md_files = [f for f in processed_files if f.endswith('.md')]
    assert len(md_files) == 10000, f"Expected 10000 .md files in processed directory, found {len(md_files)}."
    assert set(md_files) == set(raw_files), "Processed filenames do not match the raw filenames"

    for filename in raw_files:
        output_path = os.path.join(PROCESSED_DIR, filename)
        assert os.path.isfile(output_path), f"Processed output is not a regular file: {filename}"
        with open(output_path, "r") as handle:
            actual = handle.read()
        assert actual == expected_contents[filename], f"Incorrect transformed content in {filename}"

    assert not watcher.overflow, "Atomic-write event monitor overflowed"
    moved_from = {}
    atomic_destinations = set()
    for mask, cookie, name in watcher.events:
        if mask & RenameWatcher.IN_MOVED_FROM:
            moved_from[cookie] = name
        if mask & RenameWatcher.IN_MOVED_TO:
            source = moved_from.get(cookie)
            if source is not None and source != name:
                atomic_destinations.add(name)
    assert atomic_destinations == set(raw_files), (
        "Every processed file must be written to a temporary file in docs_processed "
        "and atomically renamed to its final filename"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
