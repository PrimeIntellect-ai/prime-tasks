#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import random
import re
import signal
import socket
import string
import subprocess
import threading
import time
import pytest

BASE = "/app/legacy_proc"
SERVICE = BASE + "/start_service.sh"
BENCHMARK = BASE + "/benchmark.sh"
ENGINE = BASE + "/bin/data_engine"
LOG = BASE + "/bench_results.log"


def process_tree(root_pid):
    found = {root_pid}
    changed = True
    while changed:
        changed = False
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            pid = int(name)
            try:
                with open(f"/proc/{pid}/status") as f:
                    status = f.read()
                match = re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)
                if match and int(match.group(1)) in found and pid not in found:
                    found.add(pid)
                    changed = True
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                pass
    return found


def ipv4_listener_inodes(port):
    wanted = f"{port:04X}"
    inodes = set()
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, listed_port = fields[1].split(":")
            if address == "00000000" and listed_port.upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    return inodes


def socket_inodes_for_pids(pids):
    result = set()
    for pid in pids:
        fd_dir = f"/proc/{pid}/fd"
        try:
            entries = os.listdir(fd_dir)
        except (FileNotFoundError, PermissionError):
            continue
        for entry in entries:
            try:
                target = os.readlink(f"{fd_dir}/{entry}")
            except (FileNotFoundError, PermissionError):
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match:
                result.add(match.group(1))
    return result


@contextlib.contextmanager
def running_service():
    proc = subprocess.Popen(
        [SERVICE],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        deadline = time.time() + 10
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"{SERVICE} exited before opening port 9099")
            try:
                with socket.create_connection(("127.0.0.1", 9099), timeout=0.25):
                    break
            except OSError:
                time.sleep(0.15)
        else:
            pytest.fail(f"Could not connect to service on port 9099 after running {SERVICE}")
        yield proc
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=3)


def test_start_service_script_exists():
    script_path = "/app/legacy_proc/start_service.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing"
    assert os.access(script_path, os.X_OK), f"Script {script_path} must be executable"


def test_benchmark_script_exists():
    script_path = "/app/legacy_proc/benchmark.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing"
    assert os.access(script_path, os.X_OK), f"Script {script_path} must be executable"


def test_start_service_script_contents():
    script_path = "/app/legacy_proc/start_service.sh"
    with open(script_path, "r") as f:
        content = f.read()

    assert "0x7F4A" in content, "The start_service.sh script does not contain the extracted ABI magic value (0x7F4A)."
    assert "MATRIX_ABI_MAGIC" in content, "The start_service.sh script does not export MATRIX_ABI_MAGIC."
    assert "v2" in content, "The start_service.sh script does not seem to set the library path to the v2 directory."


def test_tcp_service_responds():
    with running_service() as proc:
        listeners = ipv4_listener_inodes(9099)
        assert listeners, "The service is not listening on IPv4 0.0.0.0:9099"
        owner_sockets = socket_inodes_for_pids(process_tree(proc.pid))
        assert listeners & owner_sockets, "The wrapper process does not own the 0.0.0.0:9099 listener"

        token = "VERIFY_" + "".join(random.choice(string.ascii_letters + string.digits) for _ in range(28))
        with socket.create_connection(("127.0.0.1", 9099), timeout=2) as client:
            # Leave the connection open without input so the per-connection engine
            # remains observable while blocked in fgets().
            time.sleep(0.25)
            engine_pids = []
            for pid in process_tree(proc.pid):
                try:
                    if os.readlink(f"/proc/{pid}/exe") == ENGINE:
                        engine_pids.append(pid)
                except (FileNotFoundError, PermissionError):
                    pass
            assert engine_pids, "A connection did not spawn /app/legacy_proc/bin/data_engine"

            valid_runtime = False
            for pid in engine_pids:
                try:
                    with open(f"/proc/{pid}/environ", "rb") as f:
                        env_items = f.read().split(b"\0")
                    env = dict(item.split(b"=", 1) for item in env_items if b"=" in item)
                    with open(f"/proc/{pid}/maps") as f:
                        maps = f.read()
                except (FileNotFoundError, ProcessLookupError):
                    continue
                ld_path = env.get(b"LD_LIBRARY_PATH", b"").decode(errors="replace").split(":")
                if (env.get(b"MATRIX_ABI_MAGIC") == b"0x7F4A"
                        and BASE + "/lib/v2" in ld_path
                        and BASE + "/lib/v2/libmatrix_math.so" in maps):
                    valid_runtime = True
                    break
            assert valid_runtime, "data_engine was not run with MATRIX_ABI_MAGIC=0x7F4A and the v2 library"

            client.sendall((token + "\n").encode())
            client.shutdown(socket.SHUT_WR)
            client.settimeout(3)
            chunks = []
            while True:
                part = client.recv(4096)
                if not part:
                    break
                chunks.append(part)
            response = b"".join(chunks)
            assert response == ("Processed: " + token + "\n").encode(), \
                f"Unexpected data_engine response: {response!r}"


def test_benchmark_sends_100_requests_and_writes_log():
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass

    received = []
    stop = threading.Event()
    ready = threading.Event()
    errors = []

    def capture_server():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", 9099))
                server.listen(128)
                server.settimeout(0.2)
                ready.set()
                while not stop.is_set():
                    try:
                        conn, _ = server.accept()
                    except socket.timeout:
                        continue
                    with conn:
                        conn.settimeout(2)
                        data = b""
                        while not data.endswith(b"\n") and len(data) < 65536:
                            chunk = conn.recv(4096)
                            if not chunk:
                                break
                            data += chunk
                        received.append(data)
                        if data:
                            conn.sendall(b"Processed: " + data)
        except Exception as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=capture_server, daemon=True)
    thread.start()
    assert ready.wait(3), "Benchmark capture server did not start"
    assert not errors, f"Benchmark capture server failed: {errors}"

    try:
        result = subprocess.run(
            [BENCHMARK],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
            text=True,
        )
        # Allow the listener to finish reading the final request.
        deadline = time.time() + 2
        while len(received) < 100 and time.time() < deadline:
            time.sleep(0.05)
    finally:
        stop.set()
        thread.join(timeout=3)

    assert not errors, f"Benchmark capture server failed: {errors}"
    assert result.returncode == 0, f"benchmark.sh failed: {result.stderr}"
    assert len(received) == 100, f"benchmark.sh sent {len(received)} requests instead of 100"
    assert all(item and item.endswith(b"\n") for item in received), \
        "Every benchmark request must be nonempty and newline-terminated"
    assert os.path.isfile(LOG), "benchmark.sh did not create /app/legacy_proc/bench_results.log"
    with open(LOG, errors="replace") as f:
        log_content = f.read().strip()
    assert log_content, "bench_results.log is empty"
    assert re.search(r"\d", log_content), "bench_results.log does not contain a measured duration"
    assert re.search(r"total|execution|time|seconds?|milliseconds?|\bms\b", log_content, re.IGNORECASE), \
        "bench_results.log does not identify the total execution time"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
