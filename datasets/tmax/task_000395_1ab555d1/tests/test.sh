#!/bin/bash
mkdir -p /logs/verifier

kill_port_8080() {
python3 <<'PY'
import glob
import os
import signal
import time

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].upper().endswith(':1F90') and fields[3] == '0A':
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

pids = set()
for fd in glob.glob('/proc/[0-9]*/fd/*'):
    try:
        target = os.readlink(fd)
    except OSError:
        continue
    if target.startswith('socket:[') and target[8:-1] in inodes:
        try:
            pids.add(int(fd.split('/')[2]))
        except ValueError:
            pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
if pids:
    time.sleep(0.5)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY
}

run_checks() {
    APP=/app/vendored-async-svc-1.2.0

    test -f "$APP/start.sh" || return 1
    test -f "$APP/server.py" || return 1
    test -f /home/user/regression.py || return 1
    python3 -m py_compile "$APP/server.py" /home/user/regression.py || return 1

    # Execute the submitted regression test against an observing TCP listener.
    # It must reproduce the pcap's POST /process followed by an abortive (RST) close.
    kill_port_8080 || return 1
    python3 <<'PY' || return 1
import socket
import subprocess
import threading
import time

observations = []
ready = threading.Event()
stop = threading.Event()
errors = []

def handle(conn):
    data = bytearray()
    reset = False
    try:
        conn.settimeout(1.0)
        while True:
            try:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                data.extend(chunk)
            except ConnectionResetError:
                reset = True
                break
            except socket.timeout:
                break
    finally:
        conn.close()
    observations.append((bytes(data), reset))

def listener():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
            srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            srv.bind(('127.0.0.1', 8080))
            srv.listen(128)
            srv.settimeout(0.2)
            ready.set()
            while not stop.is_set():
                try:
                    conn, _ = srv.accept()
                except socket.timeout:
                    continue
                handle(conn)
    except BaseException as exc:
        errors.append(exc)
        ready.set()

thread = threading.Thread(target=listener, daemon=True)
thread.start()
if not ready.wait(3) or errors:
    raise AssertionError(f'Could not start regression observer: {errors!r}')

try:
    result = subprocess.run(
        ['python3', '/home/user/regression.py'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
finally:
    time.sleep(0.4)
    stop.set()
    thread.join(2)

if result.returncode != 0:
    raise AssertionError(
        f'regression.py failed with exit code {result.returncode}: '
        f'{result.stderr.decode(errors="replace")}'
    )
if errors:
    raise AssertionError(f'Regression observer failed: {errors!r}')

matched = False
for payload, was_reset in observations:
    first_line = payload.split(b'\r\n', 1)[0]
    if first_line.startswith(b'POST /process HTTP/') and was_reset:
        matched = True
        break
if not matched:
    summary = [(p[:80], r) for p, r in observations]
    raise AssertionError(
        'regression.py did not reproduce a POST /process followed by a TCP RST; '
        f'observed={summary!r}'
    )
PY

    # Import the submitted application independently of its self-reported stats.
    # Replace worker_logic with a controlled long-lived worker, signal a client
    # disconnect, and verify that the route really starts and cancels that worker.
    python3 <<'PY' || return 1
import asyncio
import importlib.util
import os
import sys

path = '/app/vendored-async-svc-1.2.0/server.py'
spec = importlib.util.spec_from_file_location('submitted_async_service', path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

if not hasattr(module, 'app') or not hasattr(module, 'worker_logic'):
    raise AssertionError('server.py must retain the FastAPI application and worker_logic')

process_routes = [
    route for route in getattr(module.app, 'routes', [])
    if getattr(route, 'path', None) == '/process' and 'POST' in getattr(route, 'methods', set())
]
if not process_routes:
    raise AssertionError('The FastAPI app has no POST /process route')
endpoint = process_routes[0].endpoint

async def exercise():
    started = asyncio.Event()
    cancelled = asyncio.Event()

    async def controlled_worker():
        started.set()
        try:
            await asyncio.sleep(60)
        except asyncio.CancelledError:
            cancelled.set()
            raise

    module.worker_logic = controlled_worker

    class DisconnectedRequest:
        async def is_disconnected(self):
            # Let a newly created worker get scheduled before reporting the RST.
            await asyncio.sleep(0)
            return started.is_set()

        async def body(self):
            return b''

    baseline = set(asyncio.all_tasks())
    handler = asyncio.create_task(endpoint(DisconnectedRequest()))

    try:
        await asyncio.wait_for(started.wait(), timeout=0.5)
    except asyncio.TimeoutError:
        handler.cancel()
        await asyncio.gather(handler, return_exceptions=True)
        raise AssertionError('POST /process did not start worker_logic')

    deadline = asyncio.get_running_loop().time() + 1.5
    while not handler.done() and asyncio.get_running_loop().time() < deadline:
        await asyncio.sleep(0.01)
    if not handler.done():
        handler.cancel()
        await asyncio.gather(handler, return_exceptions=True)
        raise AssertionError('POST /process did not react promptly to client disconnect')

    await asyncio.gather(handler, return_exceptions=True)
    await asyncio.sleep(0.05)
    if not cancelled.is_set():
        raise AssertionError('The request worker was not cancelled after client disconnect')

    current = asyncio.current_task()
    leaked = [
        task for task in asyncio.all_tasks()
        if task not in baseline and task is not current and not task.done()
    ]
    if leaked:
        for task in leaked:
            task.cancel()
        await asyncio.gather(*leaked, return_exceptions=True)
        raise AssertionError(f'Dangling asyncio tasks remained after disconnect: {leaked!r}')

asyncio.run(exercise())
PY

    # Execute the repaired start.sh itself and require the resulting service to bind.
    kill_port_8080 || return 1
    (
        cd "$APP" || exit 1
        nohup bash "$APP/start.sh" >/tmp/submitted-service.log 2>&1 &
        echo $! >/tmp/submitted-service.pid
    ) || return 1

    python3 <<'PY' || return 1
import json
import time
import urllib.request

last = None
for _ in range(80):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8080/__stats__', timeout=0.5) as response:
            data = json.loads(response.read().decode())
        value = data.get('active_tasks')
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise AssertionError('/__stats__ must expose a nonnegative integer active_tasks field')
        break
    except Exception as exc:
        last = exc
        time.sleep(0.1)
else:
    raise AssertionError(f'start.sh did not start the service on 127.0.0.1:8080: {last}; log follows: ' + open('/tmp/submitted-service.log', errors='replace').read())
PY

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import socket
import struct
import time
import json
import urllib.request
import pytest

def send_aborted_request(host, port):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        s.connect((host, port))
        request = b"POST /process HTTP/1.1\r\nHost: " + f"{host}:{port}".encode() + b"\r\nContent-Length: 0\r\n\r\n"
        s.sendall(request)
        l_onoff = 1
        l_linger = 0
        s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', l_onoff, l_linger))
        s.close()
    except Exception:
        pass

def test_no_task_leak_on_aborted_connections():
    host = '127.0.0.1'
    port = 8080
    try:
        req = urllib.request.Request(f"http://{host}:{port}/__stats__")
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
    except Exception as e:
        pytest.fail(f"Could not connect to the service at http://{host}:{port}/__stats__ to get initial stats: {e}")

    assert 'active_tasks' in data and isinstance(data['active_tasks'], int) and not isinstance(data['active_tasks'], bool)
    initial_tasks = data.get("active_tasks", 0)

    num_requests = 1000
    for _ in range(num_requests):
        send_aborted_request(host, port)

    time.sleep(2)

    try:
        req = urllib.request.Request(f"http://{host}:{port}/__stats__")
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
    except Exception as e:
        pytest.fail(f"Could not connect to the service at http://{host}:{port}/__stats__ after load test: {e}")

    assert 'active_tasks' in data and isinstance(data['active_tasks'], int) and not isinstance(data['active_tasks'], bool)
    final_tasks = data.get("active_tasks", 0)
    leaked_tasks = final_tasks - initial_tasks

    assert leaked_tasks <= 5, (
        f"Metric threshold failed: Expected <= 5 leaked tasks after {num_requests} aborted connections, "
        f"but found {leaked_tasks} leaked tasks. (Initial: {initial_tasks}, Final: {final_tasks})"
    )
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
