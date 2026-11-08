#!/bin/bash
set -e
mkdir -p /logs/verifier

# Execute the benchmark artifact the task requires, rather than trusting a
# pre-created results file.
if [ ! -f /home/user/benchmark.py ] || ! timeout 180s python3 /home/user/benchmark.py; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import json
import os
import signal
import subprocess
import time

import pytest

PROXY_DIR = "/app/vendored/goproxy-1.0"
PROXY_PATH = os.path.join(PROXY_DIR, "proxy")


def test_proxy_binary_exists():
    path = PROXY_PATH
    assert os.path.isfile(path), f"Compiled proxy binary {path} is missing. Did you run 'go build -o proxy main.go'?"
    assert os.access(path, os.X_OK), f"Compiled proxy binary {path} is not executable."


def test_benchmark_script_exists():
    assert os.path.isfile("/home/user/benchmark.py"), "Required benchmark script is missing."


def test_benchmark_results_structure():
    path = "/home/user/benchmark_results.json"
    assert os.path.isfile(path), f"Benchmark results file {path} is missing."

    with open(path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    expected_keys = {"total_requests", "successful_requests", "total_time_seconds", "requests_per_second"}
    missing_keys = expected_keys - set(results.keys())
    assert not missing_keys, f"Benchmark results missing keys: {missing_keys}"
    assert results["total_requests"] == 5000
    assert results["successful_requests"] == 5000
    assert type(results["total_time_seconds"]) in (int, float) and results["total_time_seconds"] > 0
    assert type(results["requests_per_second"]) in (int, float) and results["requests_per_second"] > 0


async def raw_get(port, path, timeout=10):
    reader = writer = None
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection("127.0.0.1", port), timeout)
        request = f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        writer.write(request.encode())
        await writer.drain()
        response = await asyncio.wait_for(reader.read(), timeout)
        status = response.split(b"\r\n", 1)[0]
        body = response.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in response else b""
        return status, body
    except Exception:
        return b"", b""
    finally:
        if writer is not None:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass


@pytest.mark.asyncio
async def test_proxy_throughput_and_correctness():
    # Confirm both requested Python backend instances are actually serving the
    # factorization API before exercising the live proxy.
    for port in (8081, 8082):
        status, body = await raw_get(port, "/factor?n=10403")
        assert status.startswith(b"HTTP/1.1 200"), f"Backend on port {port} is not serving HTTP 200."
        assert body == b"Factors of 10403", f"Backend on port {port} returned the wrong factorization response: {body!r}"

    async def fetch():
        status, body = await raw_get(8080, "/factor?n=10403")
        return status.startswith(b"HTTP/1.1 200") and body == b"Factors of 10403"

    num_requests = 10000
    concurrency = 500
    start_time = time.time()
    successful = 0
    for offset in range(0, num_requests, concurrency):
        count = min(concurrency, num_requests - offset)
        successful += sum(await asyncio.gather(*(fetch() for _ in range(count))))

    duration = time.time() - start_time
    assert successful == num_requests, (
        f"Only {successful}/{num_requests} requests returned the correct factorization response. "
        "The proxy might be dropping connections, deadlocking, or not forwarding backend responses."
    )

    rps = num_requests / duration
    threshold = 2000.0
    assert rps >= threshold, f"Throughput too low: measured {rps:.2f} RPS, expected >= {threshold} RPS."


def kill_listeners(ports):
    wanted_inodes = set()
    wanted_hex = {f"{port:04X}" for port in ports}
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = fields[1].rsplit(":", 1)[1]
                    state = fields[3]
                    if local_port in wanted_hex and state == "0A":
                        wanted_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) in (1, os.getpid()):
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in wanted_inodes:
                    victims.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


MARKER_SERVER = r'''
import asyncio
import sys

port = int(sys.argv[1])
marker = f"backend-{port}".encode()

async def handle(reader, writer):
    try:
        await reader.readuntil(b"\r\n\r\n")
        response = (b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(marker)).encode() +
                    b"\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\n" + marker)
        writer.write(response)
        await writer.drain()
    except Exception:
        pass
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", port)
    async with server:
        await server.serve_forever()

asyncio.run(main())
'''


@pytest.mark.asyncio
async def test_rebuilt_proxy_really_routes_to_both_backends():
    # Replace the live services with distinguishable test backends, rebuild the
    # submitted source using the required command, and execute that binary.
    kill_listeners({8080, 8081, 8082})
    marker_path = "/tmp/marker_backend.py"
    with open(marker_path, "w") as f:
        f.write(MARKER_SERVER)

    backends = [
        subprocess.Popen(["python3", marker_path, "8081"]),
        subprocess.Popen(["python3", marker_path, "8082"]),
    ]
    proxy = None
    try:
        build = subprocess.run(
            ["go", "build", "-o", "proxy", "main.go"],
            cwd=PROXY_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"Submitted Go source failed to build:\n{build.stderr}"
        assert os.path.isfile(PROXY_PATH) and os.access(PROXY_PATH, os.X_OK)

        proxy = subprocess.Popen([PROXY_PATH], cwd=PROXY_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        deadline = time.time() + 10
        while time.time() < deadline:
            if proxy.poll() is not None:
                stderr = proxy.stderr.read().decode(errors="replace")
                pytest.fail(f"Rebuilt proxy exited before serving requests: {stderr}")
            status, _ = await raw_get(8080, "/factor?n=2", timeout=1)
            if status.startswith(b"HTTP/1.1 200"):
                break
            await asyncio.sleep(0.1)
        else:
            pytest.fail("Rebuilt proxy did not start listening on port 8080.")

        seen = set()
        for _ in range(20):
            status, body = await raw_get(8080, "/factor?n=10403")
            assert status.startswith(b"HTTP/1.1 200"), f"Rebuilt proxy returned bad status: {status!r}"
            assert body in {b"backend-8081", b"backend-8082"}, (
                f"Proxy did not forward the backend response body; got {body!r}"
            )
            seen.add(body)
        assert seen == {b"backend-8081", b"backend-8082"}, (
            f"Requests were not routed to both hardcoded backends; observed {seen!r}"
        )
    finally:
        if proxy is not None and proxy.poll() is None:
            proxy.terminate()
            try:
                proxy.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proxy.kill()
        for process in backends:
            if process.poll() is None:
                process.terminate()
        for process in backends:
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
