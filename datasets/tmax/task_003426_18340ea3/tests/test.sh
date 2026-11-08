#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import struct
import subprocess
import threading
import time
import uuid

import pytest

APP_DIR = "/home/user/app"


def final_tcp_dst_port(path):
    with open(path, "rb") as f:
        header = f.read(24)
        assert len(header) == 24, "capture.pcap has an invalid global header"
        magic = header[:4]
        if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1"):
            endian = "<"
        elif magic in (b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d"):
            endian = ">"
        else:
            raise AssertionError("capture.pcap has an unsupported pcap format")

        final_port = None
        while True:
            packet_header = f.read(16)
            if not packet_header:
                break
            assert len(packet_header) == 16, "capture.pcap has a truncated packet header"
            _, _, captured_len, _ = struct.unpack(endian + "IIII", packet_header)
            packet = f.read(captured_len)
            assert len(packet) == captured_len, "capture.pcap has truncated packet data"

            if len(packet) < 14 or packet[12:14] != b"\x08\x00":
                continue
            ip = packet[14:]
            if len(ip) < 20 or ip[9] != 6:
                continue
            ihl = (ip[0] & 0x0f) * 4
            if ihl < 20 or len(ip) < ihl + 4:
                continue
            final_port = struct.unpack("!H", ip[ihl + 2:ihl + 4])[0]

        assert final_port is not None, "capture.pcap contains no TCP packet"
        return final_port


def stop_process_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=1)


def test_report_json():
    report_path = os.path.join(APP_DIR, "report.json")
    assert os.path.isfile(report_path), "report.json is missing"

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not valid JSON")

    assert "pcap_final_dst_port" in report, "Missing pcap_final_dst_port in report.json"
    expected_port = final_tcp_dst_port(os.path.join(APP_DIR, "capture.pcap"))
    assert expected_port == 8888
    assert report["pcap_final_dst_port"] == 8888, f"Expected pcap_final_dst_port to be 8888, got {report['pcap_final_dst_port']}"
    assert report["pcap_final_dst_port"] == expected_port, "pcap_final_dst_port does not match the final TCP packet"

    assert "deadlock_cause" in report, "Missing deadlock_cause in report.json"
    cause = report["deadlock_cause"]
    assert isinstance(cause, str) and len(cause) > 0, "deadlock_cause must be a non-empty string"
    lower = cause.lower()
    assert "lock" in lower, "deadlock_cause must identify the lock involved"
    assert any(word in lower for word in ("release", "held", "holding")), "deadlock_cause must explain that the lock remained held or unreleased"
    assert any(word in lower for word in ("error", "return", "branch", "exception")), "deadlock_cause must identify the error/return path that leaked the lock"


def test_runner_sh_fixed_and_processes_spaced_names():
    runner_path = os.path.join(APP_DIR, "runner.sh")
    assert os.path.isfile(runner_path), "runner.sh is missing"

    with open(runner_path, "r") as f:
        content = f.read()
    assert "$(ls" not in content, "runner.sh still uses the buggy '$(ls ...)' pattern which breaks on spaces."

    token = uuid.uuid4().hex
    test_files = [
        os.path.join(APP_DIR, "data", f"verification {token} one.txt"),
        os.path.join(APP_DIR, "data", f"verification {token} two.txt"),
    ]
    payloads = [f"runner-marker-one-{token}", f"runner-marker-two-{token}"]
    for path, payload in zip(test_files, payloads):
        with open(path, "w") as f:
            f.write(payload)

    received = []
    received_lock = threading.Lock()
    stop = threading.Event()
    ready = threading.Event()
    errors = []

    def handle(conn):
        try:
            conn.settimeout(1)
            chunks = []
            while True:
                try:
                    chunk = conn.recv(4096)
                except socket.timeout:
                    break
                if not chunk:
                    break
                chunks.append(chunk)
                if sum(map(len, chunks)) >= 1024 * 1024:
                    break
            with received_lock:
                received.append(b"".join(chunks).decode("utf-8", errors="replace"))
            conn.sendall(b"OK")
        except Exception as exc:
            errors.append(str(exc))
        finally:
            conn.close()

    def listener():
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            srv.bind(("127.0.0.1", 8888))
            srv.listen(50)
            srv.settimeout(0.1)
            ready.set()
            workers = []
            while not stop.is_set():
                try:
                    conn, _ = srv.accept()
                except socket.timeout:
                    continue
                t = threading.Thread(target=handle, args=(conn,))
                t.start()
                workers.append(t)
            for t in workers:
                t.join(timeout=2)
        except Exception as exc:
            errors.append(str(exc))
            ready.set()
        finally:
            srv.close()

    thread = threading.Thread(target=listener)
    thread.start()
    try:
        assert ready.wait(2), "test listener did not start"
        assert not errors, f"test listener failed: {errors}"
        result = subprocess.run(
            [runner_path], cwd=APP_DIR, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=5
        )
        assert result.returncode == 0, f"runner.sh failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        time.sleep(0.2)
    finally:
        stop.set()
        thread.join(timeout=3)
        for path in test_files:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

    assert not errors, f"listener errors while running runner.sh: {errors}"
    for payload in payloads:
        assert payload in received, f"runner.sh did not process the full spaced filename containing {payload}"


def test_server_py_fixed_and_handles_concurrent_error_requests():
    server_path = os.path.join(APP_DIR, "server.py")
    assert os.path.isfile(server_path), "server.py is missing"

    with open(server_path, "r") as f:
        content = f.read()
    if "stats_lock.acquire()" in content:
        assert content.count("stats_lock.release()") >= 2 or "finally:" in content, "server.py still seems to leak the lock on the error branch."

    proc = subprocess.Popen(
        ["python3", server_path], cwd=APP_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        start_new_session=True
    )
    try:
        deadline = time.monotonic() + 2
        while True:
            if proc.poll() is not None:
                out, err = proc.communicate()
                pytest.fail(f"server.py exited before accepting clients.\nSTDOUT:\n{out}\nSTDERR:\n{err}")
            try:
                with socket.create_connection(("127.0.0.1", 8888), timeout=0.1):
                    break
            except OSError:
                if time.monotonic() >= deadline:
                    pytest.fail("server.py did not listen on 127.0.0.1:8888")
                time.sleep(0.03)

        barrier = threading.Barrier(5)
        results = [None] * 5

        def error_client(index):
            try:
                barrier.wait(timeout=1)
                with socket.create_connection(("127.0.0.1", 8888), timeout=1.5) as sock:
                    sock.settimeout(1.5)
                    sock.sendall(b"ERROR_TRIGGER")
                    sock.shutdown(socket.SHUT_WR)
                    results[index] = sock.recv(1024)
            except Exception as exc:
                results[index] = exc

        clients = [threading.Thread(target=error_client, args=(i,)) for i in range(5)]
        for client in clients:
            client.start()
        for client in clients:
            client.join(timeout=2)
        assert all(not client.is_alive() for client in clients), "concurrent ERROR_TRIGGER clients hung"
        assert all(not isinstance(item, Exception) for item in results), f"ERROR_TRIGGER clients failed: {results}"

        with socket.create_connection(("127.0.0.1", 8888), timeout=1) as sock:
            sock.settimeout(1)
            sock.sendall(b"normal payload")
            sock.shutdown(socket.SHUT_WR)
            response = sock.recv(1024)
        assert response == b"OK", f"server did not process a normal request after error requests: {response!r}"
    finally:
        stop_process_group(proc)


def test_mre_starts_server_and_uses_five_concurrent_clients():
    mre_path = os.path.join(APP_DIR, "mre.py")
    server_path = os.path.join(APP_DIR, "server.py")
    assert os.path.isfile(mre_path), "mre.py is missing"
    assert os.path.isfile(server_path), "server.py is missing"

    with open(server_path, "rb") as f:
        original_server = f.read()
    original_mode = os.stat(server_path).st_mode
    token = uuid.uuid4().hex
    log_path = f"/tmp/mre_probe_{token}.log"

    probe = f'''import socket\nimport threading\n\nLOG = {log_path!r}\nTOKEN = {token!r}\n\ndef _log(value):\n    with open(LOG, "a") as f:\n        f.write(value + "\\n")\n\ndef start_server():\n    _log("START:" + TOKEN)\n    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)\n    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\n    srv.bind(("127.0.0.1", 8888))\n    srv.listen(10)\n    all_arrived = threading.Event()\n    lock = threading.Lock()\n    count = [0]\n    threads = []\n    def handle(conn):\n        try:\n            conn.settimeout(3)\n            data = conn.recv(4096)\n            _log("DATA:" + data.decode("utf-8", errors="replace"))\n            with lock:\n                count[0] += 1\n                if count[0] >= 5:\n                    all_arrived.set()\n            all_arrived.wait(3)\n            conn.sendall(b"ERROR")\n        finally:\n            conn.close()\n    try:\n        for _ in range(5):\n            conn, _ = srv.accept()\n            t = threading.Thread(target=handle, args=(conn,))\n            t.start()\n            threads.append(t)\n        for t in threads:\n            t.join(4)\n    finally:\n        srv.close()\n\nif __name__ == "__main__":\n    start_server()\n'''

    proc = None
    try:
        with open(server_path, "w") as f:
            f.write(probe)
        proc = subprocess.Popen(
            ["python3", mre_path], cwd=APP_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True
        )
        try:
            stdout, stderr = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            stop_process_group(proc)
            pytest.fail("mre.py timed out after 5 seconds, indicating it did not complete the concurrent reproduction")
        assert proc.returncode == 0, f"mre.py failed with return code {proc.returncode}.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}"
    finally:
        if proc is not None and proc.poll() is None:
            stop_process_group(proc)
        with open(server_path, "wb") as f:
            f.write(original_server)
        os.chmod(server_path, original_mode)

    try:
        with open(log_path, "r") as f:
            entries = [line.rstrip("\n") for line in f]
    except FileNotFoundError:
        entries = []
    finally:
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass

    assert f"START:{token}" in entries, "mre.py did not start server.py"
    payload_entries = [entry for entry in entries if entry.startswith("DATA:")]
    assert len(payload_entries) == 5, f"mre.py did not create exactly five client requests: {payload_entries}"
    assert all(entry == "DATA:ERROR_TRIGGER" for entry in payload_entries), "mre.py clients did not all send ERROR_TRIGGER"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
