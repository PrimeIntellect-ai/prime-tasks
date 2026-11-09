#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import json
import math
import os
import secrets
import signal
import socket
import stat
import subprocess
import threading
import time

import numpy as np
import requests

TOKEN = {"Authorization": "Bearer biophysics2024"}
created_files = []
processes = []


def stop_existing():
    subprocess.run(["pkill", "-f", "/app/bin/sim_server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/app/api.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.4)


def stop_process(proc):
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=3)


def wait_http(proc, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"service launcher exited early with status {proc.returncode}")
        try:
            r = requests.get("http://127.0.0.1:8080/analyze?fasta_id=readiness", timeout=0.4)
            if r.status_code == 401:
                return
        except requests.RequestException:
            pass
        time.sleep(0.1)
    raise AssertionError("API did not become ready on 127.0.0.1:8080")


def descendants_cmdlines(root_pid):
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                status = open(f"/proc/{name}/status").read().splitlines()
                ppid = int(next(x for x in status if x.startswith("PPid:")).split()[1])
            except (OSError, StopIteration, ValueError):
                continue
            pid = int(name)
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    result = []
    for pid in descendants:
        try:
            result.append(open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace"))
        except OSError:
            pass
    return result


def recv_backend(identifier, port=9000):
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.sendall(identifier.encode() + b"\n")
        data = bytearray()
        while len(data) < 16384:
            chunk = sock.recv(16384 - len(data))
            if not chunk:
                break
            data.extend(chunk)
        assert len(data) == 16384, f"backend returned {len(data)} bytes, expected 16384"
        return bytes(data)


def peak_from_raw(raw):
    matrix = np.frombuffer(raw, dtype="<f4").reshape((64, 64))
    power = np.abs(np.fft.fft2(matrix)) ** 2
    power[0, 0] = 0
    return list(map(int, np.unravel_index(np.argmax(power), power.shape)))


def check_json(identifier, expected_header, expected_peak):
    r = requests.get(f"http://127.0.0.1:8080/analyze?fasta_id={identifier}", headers=TOKEN, timeout=6)
    assert r.status_code == 200, f"Expected 200 for {identifier}, got {r.status_code}: {r.text}"
    try:
        body = r.json()
    except ValueError:
        raise AssertionError(f"Response is not JSON: {r.text}")
    assert "fasta_header" in body, "Missing 'fasta_header' in JSON response."
    assert "peak_freq" in body, "Missing 'peak_freq' in JSON response."
    assert body["fasta_header"] == expected_header, (body, expected_header)
    assert body["peak_freq"] == expected_peak, (body, expected_peak)


class MockBackend:
    def __init__(self, answers):
        self.answers = answers
        self.received = []
        self.error = None
        self.stop_event = threading.Event()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 9000))
        self.sock.listen(5)
        self.sock.settimeout(0.2)
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()

    def run(self):
        try:
            while not self.stop_event.is_set():
                try:
                    conn, _ = self.sock.accept()
                except socket.timeout:
                    continue
                with conn:
                    conn.settimeout(3)
                    request = bytearray()
                    while not request.endswith(b"\n") and len(request) < 4096:
                        part = conn.recv(4096)
                        if not part:
                            break
                        request.extend(part)
                    req = bytes(request)
                    self.received.append(req)
                    raw = self.answers.get(req)
                    if raw is None:
                        raw = bytes(16384)
                    # Deliberately fragment the response so one recv() is insufficient.
                    conn.sendall(raw[:37])
                    time.sleep(0.06)
                    for pos in range(37, len(raw), 509):
                        conn.sendall(raw[pos:pos + 509])
        except Exception as exc:
            if not self.stop_event.is_set():
                self.error = exc

    def close(self):
        self.stop_event.set()
        try:
            self.sock.close()
        except OSError:
            pass
        self.thread.join(timeout=2)


try:
    sim_path = "/app/bin/sim_server"
    start_path = "/app/start.sh"
    assert os.path.isfile(sim_path), f"Compiled backend {sim_path} is missing."
    assert os.access(sim_path, os.X_OK), f"Compiled backend {sim_path} is not executable."
    assert open(sim_path, "rb").read(4) == b"\x7fELF", "sim_server is not a compiled ELF executable"
    assert os.path.isfile(start_path), f"Startup script {start_path} is missing."
    assert os.access(start_path, os.X_OK), f"Startup script {start_path} is not executable."

    stop_existing()

    # Invoke the required composition script rather than trusting pre-running services.
    starter = subprocess.Popen([start_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    processes.append(starter)
    wait_http(starter)
    time.sleep(0.3)
    cmds = descendants_cmdlines(starter.pid)
    assert any("/app/bin/sim_server" in c and "9000" in c for c in cmds), cmds
    assert any("/app/api.py" in c and "python" in c for c in cmds), cmds
    assert starter.poll() is None, "start.sh did not wait for its background services"

    # Preserve the original authorization and missing-file assertions.
    r = requests.get("http://127.0.0.1:8080/analyze?fasta_id=protA", timeout=5)
    assert r.status_code == 401, f"Expected 401 Unauthorized, got {r.status_code}: {r.text}"
    for bad in ["Bearer biophysics2024 ", "bearer biophysics2024", "Bearer wrong"]:
        r = requests.get("http://127.0.0.1:8080/analyze?fasta_id=protA",
                         headers={"Authorization": bad}, timeout=5)
        assert r.status_code == 401, f"Authorization must match exactly; accepted {bad!r}"
    r = requests.get("http://127.0.0.1:8080/analyze?fasta_id=does_not_exist", headers=TOKEN, timeout=5)
    assert r.status_code == 404, f"Expected 404, got {r.status_code}: {r.text}"

    check_json("protA", "sp|P00001|CYC_MACMU Cytochrome c", [18, 5])
    check_json("protB", "sp|P00002|CYC_HUMAN Cytochrome c", [18, 5])

    # Exercise the compiled backend and API with a verifier-generated FASTA ID.
    dynamic_id = "dyn" + secrets.token_hex(5)
    dynamic_header = "generated header " + secrets.token_hex(8)
    dynamic_path = f"/app/data/{dynamic_id}.fasta"
    with open(dynamic_path, "w") as f:
        f.write(f">{dynamic_header}   \nACDEFG\n")
    created_files.append(dynamic_path)
    raw = recv_backend(dynamic_id)
    matrix = np.frombuffer(raw, dtype="<f4").reshape(64, 64)
    req_len = len((dynamic_id + "\n").encode())
    expected_samples = np.array([
        math.sin(2 * math.pi * (req_len * 3) * i / 64.0 + 2 * math.pi * 5 * j / 64.0)
        for i, j in [(0, 0), (1, 2), (7, 13), (31, 47)]
    ], dtype=np.float32)
    actual_samples = np.array([matrix[i, j] for i, j in [(0, 0), (1, 2), (7, 13), (31, 47)]])
    assert np.allclose(actual_samples, expected_samples, atol=2e-5), "compiled backend behavior is incorrect"
    check_json(dynamic_id, dynamic_header, peak_from_raw(raw))

    stop_process(starter)
    processes.remove(starter)
    stop_existing()

    # Replace the backend with an unpredictable verifier-controlled socket service.
    # This proves api.py sends the requested ID, reads all 16,384 bytes, and derives FFT results.
    answers = {}
    cases = []
    used_peaks = set()
    for n in range(2):
        identifier = "probe" + secrets.token_hex(6)
        header = f"private verifier header {secrets.token_hex(10)}"
        path = f"/app/data/{identifier}.fasta"
        with open(path, "w") as f:
            f.write(f">{header}\t \nSEQUENCE\n")
        created_files.append(path)
        while True:
            rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(8), "little"))
            arr = rng.normal(size=(64, 64)).astype("<f4")
            raw = arr.tobytes()
            peak = peak_from_raw(raw)
            if tuple(peak) not in used_peaks and peak != [18, 5]:
                used_peaks.add(tuple(peak))
                break
        answers[(identifier + "\n").encode()] = raw
        cases.append((identifier, header, peak))

    mock = MockBackend(answers)
    mock.start()
    api = subprocess.Popen(["python3", "/app/api.py"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, start_new_session=True)
    processes.append(api)
    wait_http(api)

    before = len(mock.received)
    r = requests.get("http://127.0.0.1:8080/analyze?fasta_id=protA", timeout=5)
    assert r.status_code == 401
    r = requests.get("http://127.0.0.1:8080/analyze?fasta_id=no_such_dynamic_file", headers=TOKEN, timeout=5)
    assert r.status_code == 404
    assert len(mock.received) == before, "API contacted backend before authorization/file validation"

    for identifier, header, peak in cases:
        check_json(identifier, header, peak)

    expected_requests = {(identifier + "\n").encode() for identifier, _, _ in cases}
    assert expected_requests.issubset(set(mock.received)), (mock.received, expected_requests)
    assert mock.error is None, repr(mock.error)

    stop_process(api)
    processes.remove(api)
    mock.close()
finally:
    for proc in list(processes):
        stop_process(proc)
    stop_existing()
    for path in created_files:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
