#!/bin/bash
set -u
mkdir -p /logs/verifier

if python3 <<'PY'
import asyncio
import collections
import http.server
import json
import os
import pathlib
import pwd
import random
import signal
import socket
import socketserver
import subprocess
import threading
import time

APP = pathlib.Path('/home/user/app')
SOURCE = APP / 'proxy' / 'main.cpp'
BUILD = APP / 'proxy' / 'build'
BINARY = BUILD / 'proxy'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def clear_port(port):
    subprocess.run(['fuser', '-k', f'{port}/tcp'], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)


require(SOURCE.is_file(), 'Missing /home/user/app/proxy/main.cpp')
require(SOURCE.read_text(errors='replace').strip() != '#include <iostream>\nint main() {\n    std::cout << "Naive proxy running..." << std::endl;\n    return 0;\n}',
        'The proxy source is still the original placeholder')

clear_port(8080)
clear_port(8081)
subprocess.run(['rm', '-rf', str(BUILD)], check=True)
BUILD.mkdir(parents=True)
configure = subprocess.run(['cmake', '..'], cwd=BUILD, capture_output=True, text=True, timeout=60)
require(configure.returncode == 0, f'CMake configuration failed:\n{configure.stdout}\n{configure.stderr}')
build = subprocess.run(['cmake', '--build', '.', '-j2'], cwd=BUILD,
                       capture_output=True, text=True, timeout=120)
require(build.returncode == 0, f'Proxy build failed:\n{build.stdout}\n{build.stderr}')
require(BINARY.is_file() and os.access(BINARY, os.X_OK), 'CMake did not produce an executable named proxy')
require(BINARY.read_bytes()[:4] == b'\x7fELF', 'Built proxy is not an ELF executable')

rng = random.SystemRandom()
ids = rng.sample(range(10000, 90000), 5)
root_id, middle_id, target_id, branch_id, bad_id = ids
base = [rng.randrange(-500, 501) for _ in range(32)]
diff1 = [rng.randrange(-30, 31) for _ in base]
diff2 = [rng.randrange(-30, 31) for _ in base]
branch_diff = [rng.randrange(-30, 31) for _ in base]
bad_diff = [rng.randrange(-30, 31) for _ in base]
middle = [a + b for a, b in zip(base, diff1)]
target = [a + b for a, b in zip(middle, diff2)]
branch = [a + b for a, b in zip(target, branch_diff)]
bad_value = [a + b for a, b in zip(target, bad_diff)]

artifacts = {
    root_id: (None, base, base, sum(base) % 256),
    middle_id: (root_id, diff1, middle, sum(middle) % 256),
    target_id: (middle_id, diff2, target, sum(target) % 256),
    branch_id: (target_id, branch_diff, branch, sum(branch) % 256),
    bad_id: (target_id, bad_diff, bad_value, (sum(bad_value) + 1) % 256),
}

state_lock = threading.Lock()
request_times = collections.deque()
events = []
violations = 0


class BackendHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):
        pass

    def send_json(self, status, value):
        payload = json.dumps(value, separators=(',', ':')).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        global violations
        now = time.monotonic()
        with state_lock:
            while request_times and now - request_times[0] >= 1.0:
                request_times.popleft()
            limited = len(request_times) >= 5
            request_times.append(now)
            events.append((now, self.path, limited))
            if limited:
                violations += 1
        if limited:
            self.send_json(429, {'error': 'rate limit exceeded'})
            return

        parts = self.path.split('?', 1)[0].strip('/').split('/')
        if len(parts) != 2 or parts[0] not in ('metadata', 'download'):
            self.send_json(404, {'error': 'not found'})
            return
        try:
            artifact_id = int(parts[1])
        except ValueError:
            self.send_json(404, {'error': 'not found'})
            return
        item = artifacts.get(artifact_id)
        if item is None:
            self.send_json(404, {'error': 'not found'})
            return
        parent, download, reconstructed, checksum = item
        if parts[0] == 'metadata':
            self.send_json(200, {
                'id': artifact_id,
                'parent': parent,
                'parent_id': parent,
                'checksum': checksum,
                'is_diff': parent is not None,
            })
        else:
            self.send_json(200, download)


class ThreadedServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


backend = ThreadedServer(('127.0.0.1', 8081), BackendHandler)
backend_thread = threading.Thread(target=backend.serve_forever, daemon=True)
backend_thread.start()

user = pwd.getpwnam('user')

def demote():
    os.setsid()
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)

proxy = subprocess.Popen([str(BINARY)], cwd=BUILD, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         preexec_fn=demote)

try:
    deadline = time.monotonic() + 10
    while True:
        if proxy.poll() is not None:
            raise AssertionError(f'Proxy exited before listening (status {proxy.returncode})')
        try:
            with socket.create_connection(('127.0.0.1', 8080), timeout=0.2):
                break
        except OSError:
            if time.monotonic() >= deadline:
                raise AssertionError('Proxy did not listen on 127.0.0.1:8080')
            time.sleep(0.05)

    import aiohttp

    async def fetch(session, artifact_id, timeout=25):
        async with session.get(f'http://127.0.0.1:8080/artifact/{artifact_id}',
                               timeout=aiohttp.ClientTimeout(total=timeout)) as response:
            body = await response.read()
            return response.status, body

    def decode(body):
        try:
            return json.loads(body.decode())
        except Exception as exc:
            raise AssertionError(f'Proxy returned invalid JSON: {body[:300]!r}') from exc

    async def behavioral_tests():
        connector = aiohttp.TCPConnector(limit=250)
        async with aiohttp.ClientSession(connector=connector) as session:
            status, body = await fetch(session, target_id)
            require(status == 200, f'Dependency-chain request returned HTTP {status}: {body[:300]!r}')
            require(decode(body) == target, 'Proxy reconstructed the dependency chain incorrectly')

            await asyncio.sleep(0.1)
            with state_lock:
                before_cached = len(events)
            repeated = await asyncio.gather(*(fetch(session, target_id) for _ in range(40)))
            require(all(status == 200 and decode(body) == target for status, body in repeated),
                    'Concurrent cached requests did not all return the correct artifact')
            await asyncio.sleep(0.1)
            with state_lock:
                after_cached = len(events)
            require(after_cached == before_cached,
                    'Repeated requests contacted the backend instead of using the local cache')

            status, body = await fetch(session, branch_id)
            require(status == 200 and decode(body) == branch,
                    'Proxy failed to reconstruct a new child from a cached parent')

            status, body = await fetch(session, bad_id)
            require(status < 200 or status >= 300,
                    'Proxy served an artifact whose reconstructed checksum is invalid')

            # This is the trusted replacement for the writable, self-reporting benchmark.
            total = 10000
            workers = 200
            next_index = 0
            index_lock = asyncio.Lock()
            successes = 0

            async def worker():
                nonlocal next_index, successes
                while True:
                    async with index_lock:
                        if next_index >= total:
                            return
                        next_index += 1
                    st, data = await fetch(session, target_id, timeout=30)
                    if st == 200 and decode(data) == target:
                        successes += 1

            started = time.monotonic()
            await asyncio.gather(*(worker() for _ in range(workers)))
            elapsed = time.monotonic() - started
            throughput = total / elapsed
            success_rate = successes * 100.0 / total
            print(f'Throughput: {throughput:.2f} req/s')
            print(f'Success rate: {success_rate:.2f}%')
            require(throughput >= 500.0,
                    f'Throughput was {throughput:.2f} req/s, expected >= 500.0 req/s')
            require(success_rate == 100.0,
                    f'Success rate was {success_rate}%, expected 100.0%')

    asyncio.run(behavioral_tests())
    with state_lock:
        observed_violations = violations
        observed_events = list(events)
    require(observed_violations == 0,
            f'Proxy exceeded 5 backend requests/second ({observed_violations} rate-limited requests)')
    require(any(path == f'/metadata/{target_id}' for _, path, _ in observed_events),
            'Proxy never requested metadata for the tested artifact')
    require(any(path == f'/download/{root_id}' for _, path, _ in observed_events),
            'Proxy never downloaded the base artifact')
finally:
    backend.shutdown()
    backend.server_close()
    try:
        os.killpg(proxy.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        proxy.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proxy.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    clear_port(8080)
    clear_port(8081)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
