#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import collections
import concurrent.futures
import json
import os
import random
import re
import signal
import socket
import subprocess
import threading
import time
import uuid

ROOT = "/app/telemetry_env"
SRC_DIR = ROOT + "/src"
SOURCE = SRC_DIR + "/ingestor.cpp"
MAKEFILE = SRC_DIR + "/Makefile"
BINARY = ROOT + "/bin/telemetry_ingestor"
SINK_SCRIPT = ROOT + "/sink.sh"
CLEAN_DIR = ROOT + "/corpora/clean"
EVIL_DIR = ROOT + "/corpora/evil"
DROPPED_LOG = "/tmp/dropped_payloads.log"

children = []


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def stop_shipped_services():
    # Stop only the named services supplied by this task, not unrelated processes.
    for pid_text in os.listdir("/proc"):
        if not pid_text.isdigit() or int(pid_text) == os.getpid():
            continue
        try:
            with open(f"/proc/{pid_text}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode("utf-8", "ignore")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if BINARY in cmd or SINK_SCRIPT in cmd or "nc -l -p 9090" in cmd:
            try:
                os.kill(int(pid_text), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
    time.sleep(0.3)


def wait_alive(proc, description):
    time.sleep(0.4)
    assert proc.poll() is None, f"{description} exited during startup"


def send_udp(payload):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(payload, ("127.0.0.1", 8080))


def corpus(directory):
    result = []
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            payload = f.read()
        parsed = json.loads(payload.decode("utf-8"))
        assert isinstance(parsed.get("id"), str) and parsed["id"], f"Corpus payload lacks an id: {path}"
        result.append((parsed["id"], payload))
    assert result, f"Corpus is empty: {directory}"
    return result


class TcpCollector:
    def __init__(self):
        self.data = bytearray()
        self.lock = threading.Lock()
        self.stop_event = threading.Event()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 9090))
        self.sock.listen(64)
        self.sock.settimeout(0.2)
        self.thread = threading.Thread(target=self._accept, daemon=True)
        self.readers = []

    def start(self):
        self.thread.start()

    def _accept(self):
        while not self.stop_event.is_set():
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            reader = threading.Thread(target=self._read, args=(conn,), daemon=True)
            self.readers.append(reader)
            reader.start()

    def _read(self, conn):
        with conn:
            conn.settimeout(0.2)
            while not self.stop_event.is_set():
                try:
                    chunk = conn.recv(65536)
                except socket.timeout:
                    continue
                except OSError:
                    return
                if not chunk:
                    return
                with self.lock:
                    self.data.extend(chunk)

    def snapshot(self):
        with self.lock:
            return bytes(self.data)

    def close(self):
        self.stop_event.set()
        try:
            self.sock.close()
        except OSError:
            pass
        self.thread.join(timeout=1)


def read_drop_lines():
    if not os.path.exists(DROPPED_LOG):
        return []
    with open(DROPPED_LOG, "r", encoding="utf-8", errors="strict") as f:
        return f.read().splitlines()


def wait_for(predicate, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.1)
    return predicate()


def start_ingestor():
    proc = subprocess.Popen([BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    children.append(proc)
    wait_alive(proc, "telemetry_ingestor")
    return proc


def verify_makefile_and_source():
    assert os.path.isfile(MAKEFILE), f"Makefile missing at {MAKEFILE}"
    with open(MAKEFILE, "r", encoding="utf-8") as f:
        make_text = f.read()
    assert "/opt/libser/v2" in make_text, "Makefile does not link against /opt/libser/v2"
    assert "/opt/libser/v1" not in make_text, "Makefile still references /opt/libser/v1"

    assert os.path.isfile(SOURCE), f"Source missing at {SOURCE}"
    with open(SOURCE, "r", encoding="utf-8") as f:
        source_text = f.read()
    assert re.search(r"\bassert\s*\(", source_text), "ingestor.cpp lacks the required intermediate assert() checks"
    assert re.search(r"\b(mutex|lock_guard|unique_lock|scoped_lock)\b", source_text), "worker queue has no synchronization primitive"


def rebuild():
    if os.path.exists(BINARY):
        os.remove(BINARY)
    result = subprocess.run(["make", "-C", SRC_DIR, "all"], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=45)
    assert result.returncode == 0, "Rebuilding telemetry_ingestor failed:\n" + result.stdout
    assert os.path.isfile(BINARY), f"Compiled binary missing at {BINARY}"
    assert os.access(BINARY, os.X_OK), "Compiled ingestor is not executable"


def verify_with_real_sink():
    output_path = "/tmp/verifier_sink_output"
    try:
        os.remove(output_path)
    except FileNotFoundError:
        pass
    out = open(output_path, "wb")
    sink = subprocess.Popen([SINK_SCRIPT], stdout=out, stderr=subprocess.DEVNULL)
    children.append(sink)
    wait_alive(sink, "sink.sh")
    ingestor = start_ingestor()

    probe_id = "clean_sink_probe_" + uuid.uuid4().hex
    probe = json.dumps({"id": probe_id, "data": "normal telemetry data"}, separators=(",", ":")).encode()
    send_udp(probe)

    def received():
        out.flush()
        try:
            with open(output_path, "rb") as f:
                return probe in f.read()
        except FileNotFoundError:
            return False

    assert wait_for(received, 6), "A clean UDP payload did not reach the provided TCP sink on port 9090"
    stop_process(ingestor)
    stop_process(sink)
    out.close()
    children.remove(ingestor)
    children.remove(sink)


def verify_adversarial_pipeline():
    try:
        os.remove(DROPPED_LOG)
    except FileNotFoundError:
        pass

    clean = corpus(CLEAN_DIR)
    evil = corpus(EVIL_DIR)

    # Valid multibyte UTF-8 is placed near common receive/decode boundaries.
    clean_dynamic = []
    for i in range(16):
        ident = "clean_" + uuid.uuid4().hex
        text = ("x" * (1000 + i)) + "€漢🙂" + ("y" * 19)
        payload = json.dumps({"id": ident, "data": text}, ensure_ascii=False,
                             separators=(",", ":")).encode("utf-8")
        clean_dynamic.append((ident, payload))

    evil_dynamic = []
    for i in range(16):
        ident = "evil_" + uuid.uuid4().hex
        attack = f"../../../../etc/passwd; /bin/sh -c exploit_{i}"
        payload = json.dumps({"id": ident, "data": attack}, separators=(",", ":")).encode()
        evil_dynamic.append((ident, payload))

    collector = TcpCollector()
    collector.start()
    ingestor = start_ingestor()
    try:
        # Preserve the original clean-then-evil corpus check.
        for _, payload in clean:
            send_udp(payload)
            time.sleep(0.01)
        assert wait_for(lambda: all(payload in collector.snapshot() for _, payload in clean), 10), \
            "Not all clean corpus payloads were forwarded to TCP port 9090"
        assert read_drop_lines() == [], "One or more clean corpus payloads were incorrectly dropped"

        for _, payload in evil:
            send_udp(payload)
            time.sleep(0.01)

        # Concurrent, unpredictable inputs exercise queue synchronization and prevent
        # passing by printing a fixed number of fabricated DROPPED lines.
        mixed = clean_dynamic + evil_dynamic
        random.shuffle(mixed)
        chunks = [mixed[i::4] for i in range(4)]

        def sender(items):
            for _, payload in items:
                send_udp(payload)
                time.sleep(0.004)

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            futures = [pool.submit(sender, chunk) for chunk in chunks]
            for future in futures:
                future.result(timeout=10)

        expected_evil_ids = [ident for ident, _ in evil + evil_dynamic]
        expected_clean_payloads = [payload for _, payload in clean + clean_dynamic]

        assert wait_for(lambda: len(read_drop_lines()) >= len(expected_evil_ids), 12), \
            "Timed out waiting for all malicious payload classifications"
        assert wait_for(lambda: all(p in collector.snapshot() for p in expected_clean_payloads), 12), \
            "Not all clean payloads reached the TCP sink"
        assert ingestor.poll() is None, "telemetry_ingestor crashed under concurrent load"

        lines = read_drop_lines()
        prefix = "DROPPED: "
        assert all(line.startswith(prefix) and len(line) > len(prefix) for line in lines), \
            "Dropped log contains malformed lines"
        actual_ids = [line[len(prefix):] for line in lines]
        assert collections.Counter(actual_ids) == collections.Counter(expected_evil_ids), \
            "Dropped log IDs do not exactly match the malicious payload IDs"

        captured = collector.snapshot()
        for _, payload in evil + evil_dynamic:
            assert payload not in captured, "A malicious payload was forwarded to the TCP sink"
        for _, payload in clean + clean_dynamic:
            assert payload in captured, "A clean payload was not forwarded to the TCP sink"
    finally:
        stop_process(ingestor)
        if ingestor in children:
            children.remove(ingestor)
        collector.close()


def leave_services_running():
    sink_log = open("/tmp/final_sink_output.log", "ab", buffering=0)
    sink = subprocess.Popen([SINK_SCRIPT], stdout=sink_log, stderr=subprocess.DEVNULL,
                            start_new_session=True)
    time.sleep(0.25)
    ingestor = subprocess.Popen([BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                start_new_session=True)
    time.sleep(0.4)
    assert sink.poll() is None, "sink.sh is not running after verification"
    assert ingestor.poll() is None, "telemetry_ingestor is not running after verification"


def main():
    verify_makefile_and_source()

    # Retain the original final-state assertions before replacing the process with
    # a verifier-controlled build.
    assert os.path.isfile(BINARY), f"Compiled binary missing at {BINARY}"
    running = subprocess.run(["pgrep", "-f", "telemetry_ingestor"], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True)
    assert running.returncode == 0 and running.stdout.strip(), "telemetry_ingestor process is not running"

    stop_shipped_services()
    rebuild()
    verify_with_real_sink()
    stop_shipped_services()
    verify_adversarial_pipeline()
    stop_shipped_services()
    leave_services_running()


try:
    main()
except Exception:
    for proc in reversed(children):
        stop_process(proc)
    raise
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
