#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import heapq
import http.client
import os
import re
import subprocess
import sys
import threading
import time


def get_rss_bytes(pid):
    try:
        with open(f"/proc/{pid}/status", "r") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1]) * 1024
    except (OSError, ValueError):
        pass
    return 0


def get_listening_port(pid):
    inodes = set()
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                link = os.readlink(f"/proc/{pid}/fd/{fd}")
                if link.startswith("socket:[") and link.endswith("]"):
                    inodes.add(link[8:-1])
            except OSError:
                pass
    except OSError:
        return None

    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                for line in list(f)[1:]:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A" and fields[9] in inodes:
                        return int(fields[1].rsplit(":", 1)[1], 16)
        except OSError:
            pass
    return None


def smooth_numbers(count):
    values = []
    queue = [1]
    seen = {1}
    limit = (1 << 63) - 1
    while queue and len(values) < count:
        value = heapq.heappop(queue)
        values.append(value)
        for prime in (2, 3, 5, 7, 11):
            new_value = value * prime
            if new_value <= limit and new_value not in seen:
                seen.add(new_value)
                heapq.heappush(queue, new_value)
    assert len(values) == count
    return values


def expected_body(number):
    factors = []
    remaining = number
    divisor = 2
    while divisor <= remaining:
        while remaining % divisor == 0:
            factors.append(divisor)
            remaining //= divisor
        divisor += 1
    return "[" + " ".join(str(x) for x in factors) + "]"


def test_math_service_memory_leak():
    binary_path = "/home/user/math-service-fixed"
    assert os.path.exists(binary_path), f"Binary not found at {binary_path}"
    assert os.path.isfile(binary_path), f"Artifact at {binary_path} is not a regular file"
    assert os.access(binary_path, os.X_OK), f"File at {binary_path} is not executable"

    build_info = subprocess.run(
        ["go", "version", "-m", binary_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert build_info.returncode == 0 and "go1." in build_info.stdout, (
        "The submitted artifact is not a Go executable"
    )

    source_binary = "/app/math-service/bin/math-service"
    try:
        os.remove(source_binary)
    except FileNotFoundError:
        pass
    build = subprocess.run(
        ["make", "-C", "/app/math-service", "build"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"The repaired Makefile does not build successfully:\n{build.stdout}"
    assert os.path.isfile(source_binary) and os.access(source_binary, os.X_OK), (
        "The Makefile build target did not produce executable bin/math-service"
    )

    env = os.environ.copy()
    old_godebug = env.get("GODEBUG", "")
    env["GODEBUG"] = (old_godebug + "," if old_godebug else "") + "gctrace=1"
    process = subprocess.Popen(
        [binary_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )

    stdout_data = bytearray()
    stderr_data = bytearray()

    def drain(stream, destination):
        while True:
            chunk = stream.read(4096)
            if not chunk:
                return
            destination.extend(chunk)

    stdout_thread = threading.Thread(target=drain, args=(process.stdout, stdout_data), daemon=True)
    stderr_thread = threading.Thread(target=drain, args=(process.stderr, stderr_data), daemon=True)
    stdout_thread.start()
    stderr_thread.start()

    stop_monitor = threading.Event()
    rss_samples = []

    def monitor_memory():
        while not stop_monitor.is_set():
            rss_samples.append(get_rss_bytes(process.pid))
            time.sleep(0.01)

    monitor_thread = threading.Thread(target=monitor_memory, daemon=True)

    try:
        port = None
        for _ in range(100):
            if process.poll() is not None:
                raise AssertionError("Service exited before opening a listening socket")
            port = get_listening_port(process.pid)
            if port is not None:
                break
            time.sleep(0.05)
        assert port is not None, "Service did not open a listening TCP socket"

        numbers = smooth_numbers(50000)
        expected = [expected_body(number) for number in numbers]
        monitor_thread.start()
        started = time.monotonic()

        def worker(indices):
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
            completed = 0
            try:
                for index in indices:
                    number = numbers[index]
                    connection.request("GET", f"/factorize?n={number}")
                    response = connection.getresponse()
                    body = response.read().decode("utf-8", "strict")
                    assert response.status == 200, (
                        f"Request for n={number} returned HTTP {response.status}"
                    )
                    assert body == expected[index], (
                        f"Incorrect factorization for {number}: got {body!r}, "
                        f"expected {expected[index]!r}"
                    )
                    completed += 1
            finally:
                connection.close()
            return completed

        worker_count = 8
        partitions = [range(i, len(numbers), worker_count) for i in range(worker_count)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=worker_count) as executor:
            futures = [executor.submit(worker, part) for part in partitions]
            completed = sum(future.result(timeout=30) for future in futures)

        elapsed = time.monotonic() - started
        assert completed == 50000, f"Only {completed} of 50000 requests completed successfully"
        assert elapsed <= 30, f"The 50000-request run took too long ({elapsed:.2f}s)"
        assert process.poll() is None, "Service exited during the load test"

        rss_samples.append(get_rss_bytes(process.pid))
        max_rss = max(rss_samples or [0])
        assert max_rss <= 50 * 1024 * 1024, (
            f"Maximum RSS was {max_rss / (1024 * 1024):.2f} MB, exceeding 50 MB"
        )
    finally:
        stop_monitor.set()
        if monitor_thread.is_alive():
            monitor_thread.join(timeout=1)
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        stdout_thread.join(timeout=1)
        stderr_thread.join(timeout=1)

    trace = stderr_data.decode("utf-8", "replace")
    heap_samples_mb = []
    for match in re.finditer(r"([0-9.]+)->([0-9.]+)->([0-9.]+) MB", trace):
        # The first two gctrace values are runtime heap sizes at GC start/end.
        heap_samples_mb.extend((float(match.group(1)), float(match.group(2))))
    assert heap_samples_mb, "No Go runtime GC memory statistics were emitted"
    max_heap_mb = max(heap_samples_mb)
    assert max_heap_mb <= 50.0, (
        f"Maximum Go runtime heap allocation was {max_heap_mb:.2f} MB, exceeding 50 MB"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
