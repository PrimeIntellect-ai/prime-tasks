#!/bin/bash
set +e
mkdir -p /logs/verifier
ok=1

# The submitted C++ project must actually build using make.
if ! timeout 45s make -B -C /home/user/workspace/cpp_server; then
    ok=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import concurrent.futures
import difflib
import os
import socket
import subprocess
import tempfile
import pytest

HOST = "127.0.0.1"
PORT = 8080


def exchange(payload):
    try:
        with socket.create_connection((HOST, PORT), timeout=5) as s:
            s.settimeout(8)
            s.sendall(payload)
            data = b""
            while b"\n" not in data:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
            return data.decode("utf-8").strip()
    except Exception as e:
        pytest.fail(f"Failed to connect or communicate with server at {HOST}:{PORT}: {e}")


def make_case(index):
    token = os.urandom(12).hex()
    old_lines = [
        f"release={token}\n",
        f"component={index}-{os.urandom(5).hex()}\n",
        "enabled=false\n",
        f"payload={os.urandom(18).hex()}\n",
    ]
    new_lines = [
        f"release={token}\n",
        f"component={index}-{os.urandom(5).hex()}\n",
        "enabled=true\n",
        f"payload={os.urandom(18).hex()}\n",
        f"validated={os.urandom(8).hex()}\n",
    ]
    old = "".join(old_lines).encode()
    new = "".join(new_lines).encode()
    patch = "".join(difflib.unified_diff(
        old.decode().splitlines(True),
        new.decode().splitlines(True),
        fromfile=f"old-{token}.txt",
        tofile=f"new-{token}.txt",
    )).encode()
    with tempfile.NamedTemporaryFile() as f:
        f.write(new)
        f.flush()
        signature = subprocess.check_output(["/app/sig_gen", f.name], text=True).strip()
    request = b"VALIDATE " + base64.b64encode(old) + b" " + base64.b64encode(patch) + b"\n"
    return request, "SUCCESS " + signature


def test_server_valid_patch():
    host = "127.0.0.1"
    port = 8080

    payload = b"VALIDATE SGVsbG8gV29ybGQhCg== LS0tIG9sZC50eHQJMjAyMy0xMC0yNCAxMjozNDo1Ni4wMDAwMDAwMDAgKzAwMDAKKysrIG5ldy50eHQJMjAyMy0xMC0yNCAxMjozNToxMi4wMDAwMDAwMDAgKzAwMDAKQEAgLTEgKzEgQEAKLUhlbGxvIFdvcmxkIQorSGVsbG8gQysrIQo=\n"

    try:
        with socket.create_connection((host, port), timeout=5) as s:
            s.sendall(payload)
            response = s.recv(1024).decode('utf-8').strip()
    except Exception as e:
        pytest.fail(f"Failed to connect or communicate with server at {host}:{port}: {e}")

    assert response == "SUCCESS 7C743489", f"Expected 'SUCCESS 7C743489', but got '{response}'"


def test_server_invalid_patch():
    host = "127.0.0.1"
    port = 8080

    # "fake patch" base64 is ZmFrZSBwYXRjaA==
    payload = b"VALIDATE SGVsbG8gV29ybGQhCg== ZmFrZSBwYXRjaA==\n"

    try:
        with socket.create_connection((host, port), timeout=5) as s:
            s.sendall(payload)
            response = s.recv(1024).decode('utf-8').strip()
    except Exception as e:
        pytest.fail(f"Failed to connect or communicate with server at {host}:{port}: {e}")

    assert response == "ERROR PATCH_FAILED", f"Expected 'ERROR PATCH_FAILED', but got '{response}'"


def test_runtime_generated_patches_and_signatures():
    cases = [make_case(i) for i in range(12)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        responses = list(pool.map(lambda case: exchange(case[0]), cases))
    for response, (_, expected) in zip(responses, cases):
        assert response == expected


def test_runtime_generated_invalid_patches():
    for _ in range(4):
        base = os.urandom(30).hex().encode() + b"\n"
        invalid_patch = b"not a unified patch " + os.urandom(24)
        request = b"VALIDATE " + base64.b64encode(base) + b" " + base64.b64encode(invalid_patch) + b"\n"
        assert exchange(request) == "ERROR PATCH_FAILED"
TEST_EOF

if [ "$ok" -eq 1 ]; then
    if ! timeout 60s python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
        ok=0
    fi
fi

# Locate and stop the submitted listener so the Go runner can be exercised
# against an instrumented validation endpoint.
cat << 'PY_EOF' > /tmp/stop_8080.py
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                local = fields[1]
                state = fields[3]
                if local.rsplit(":", 1)[-1].upper() == "1F90" and state == "0A":
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

pids = set()
for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(name))
    except OSError:
        pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

time.sleep(0.5)
for pid in pids:
    try:
        os.kill(pid, 0)
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY_EOF

cat << 'PY_EOF' > /tmp/runner_mock.py
import base64
import json
import os
import signal
import socket
import subprocess
import tempfile
import threading
import time

stop = threading.Event()
lock = threading.Lock()
valid = 0
total = 0
active = 0
max_active = 0
threads = []


def on_signal(signum, frame):
    stop.set()

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)


def handle(conn):
    global valid, total, active, max_active
    with lock:
        active += 1
        max_active = max(max_active, active)
    try:
        conn.settimeout(5)
        data = b""
        while b"\n" not in data and len(data) < 4 * 1024 * 1024:
            chunk = conn.recv(65536)
            if not chunk:
                break
            data += chunk
        response = "ERROR PATCH_FAILED"
        is_valid = False
        try:
            parts = data.splitlines()[0].split()
            if len(parts) == 3 and parts[0] == b"VALIDATE":
                base = base64.b64decode(parts[1], validate=True)
                patch_data = base64.b64decode(parts[2], validate=True)
                with tempfile.TemporaryDirectory() as d:
                    base_path = os.path.join(d, "base.txt")
                    patch_path = os.path.join(d, "change.patch")
                    with open(base_path, "wb") as f:
                        f.write(base)
                    with open(patch_path, "wb") as f:
                        f.write(patch_data)
                    result = subprocess.run(
                        ["patch", "--batch", "--silent", base_path, patch_path],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=5,
                    )
                    if result.returncode == 0:
                        sig = subprocess.check_output(["/app/sig_gen", base_path], text=True, timeout=5).strip()
                        response = "SUCCESS " + sig
                        is_valid = True
        except Exception:
            pass
        with lock:
            total += 1
            if is_valid:
                valid += 1
        # Keep requests overlapping long enough to distinguish concurrent
        # goroutines from a sequential loop.
        time.sleep(0.15)
        conn.sendall((response + "\n").encode())
    finally:
        try:
            conn.close()
        except Exception:
            pass
        with lock:
            active -= 1


server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 8080))
server.listen(100)
server.settimeout(0.2)
with open("/tmp/runner_mock.ready", "w") as f:
    f.write("ready")

start = time.time()
while not stop.is_set() and time.time() - start < 45:
    with lock:
        done = valid >= 50
    if done:
        break
    try:
        conn, _ = server.accept()
    except socket.timeout:
        continue
    t = threading.Thread(target=handle, args=(conn,))
    t.start()
    threads.append(t)

server.close()
for t in threads:
    t.join(timeout=6)
with lock:
    report = {"valid": valid, "total": total, "max_active": max_active}
with open("/tmp/runner_report.json", "w") as f:
    json.dump(report, f)
PY_EOF

runner_exercised=0
if [ "$ok" -eq 1 ]; then
    python3 /tmp/stop_8080.py
    rm -f /tmp/runner_mock.ready /tmp/runner_report.json
    python3 /tmp/runner_mock.py >/tmp/runner_mock.log 2>&1 &
    mock_pid=$!

    for _ in $(seq 1 50); do
        [ -f /tmp/runner_mock.ready ] && break
        sleep 0.1
    done

    if [ ! -f /tmp/runner_mock.ready ]; then
        ok=0
    else
        runner_exercised=1
        if ! (cd /home/user/workspace/go_runner && timeout 40s go run main.go); then
            ok=0
        fi
    fi

    kill -TERM "$mock_pid" 2>/dev/null || true
    wait "$mock_pid" 2>/dev/null || true

    if [ "$runner_exercised" -eq 1 ]; then
        if ! python3 - << 'PY_EOF'
import json
with open('/tmp/runner_report.json') as f:
    report = json.load(f)
assert report['valid'] == 50, report
assert report['total'] == 50, report
assert report['max_active'] >= 2, report
PY_EOF
        then
            ok=0
        fi
    fi

    # Restore the submitted server and leave it listening as required.
    cd /home/user/workspace/cpp_server
    nohup ./server >/tmp/cpp_server_verifier.log 2>&1 </dev/null &
    cd - >/dev/null
    if ! python3 - << 'PY_EOF'
import socket
import time
for _ in range(60):
    try:
        with socket.create_connection(('127.0.0.1', 8080), timeout=0.2):
            raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit(1)
PY_EOF
    then
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
