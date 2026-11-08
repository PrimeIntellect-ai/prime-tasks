#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import http.server
import os
import random
import shutil
import socketserver
import string
import subprocess
import threading
import time
import urllib.error
import urllib.request

import pytest

POOL_ROOT = "/home/user/storage"
POOLS = {
    "pool1": os.path.join(POOL_ROOT, "pool1"),
    "pool2": os.path.join(POOL_ROOT, "pool2"),
}
LIMIT = 10485760


def clear_pools():
    for directory in POOLS.values():
        os.makedirs(directory, exist_ok=True)
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)


def make_file(pool, relative_path, size):
    path = os.path.join(POOLS[pool], relative_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.truncate(size)
    return path


def health():
    request = urllib.request.Request("http://localhost:8080/health")
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            return response.status, response.read().decode("utf-8").strip()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8").strip()


@pytest.fixture(scope="module")
def go_server():
    source_path = "/home/user/fs_monitor.go"
    binary_path = "/home/user/fs_monitor"
    assert os.path.isfile(source_path), f"Go source not found at {source_path}"
    assert os.path.isfile(binary_path), f"Compiled Go binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Go binary at {binary_path} is not executable"
    with open(binary_path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "fs_monitor is not an ELF executable"
    result = subprocess.run(["go", "version", "-m", binary_path], capture_output=True, text=True)
    assert result.returncode == 0 and "go" in result.stdout.lower(), "fs_monitor is not a Go executable"

    clear_pools()
    process = subprocess.Popen([binary_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    server_up = False
    for _ in range(30):
        if process.poll() is not None:
            break
        try:
            health()
            server_up = True
            break
        except Exception:
            time.sleep(0.25)
    if not server_up:
        process.terminate()
        pytest.fail("Go server did not start or bind to port 8080")

    yield process

    clear_pools()
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


@pytest.fixture(scope="module")
def instrumented_allocator():
    allocator = "/home/user/tools/allocator"
    with open(allocator, "rb") as handle:
        original = handle.read()
    original_mode = os.stat(allocator).st_mode
    replacement = r'''#!/bin/bash
printf 'Enter pool to manage: '
IFS= read -r pool
printf 'Select action (expand/shrink): '
IFS= read -r action
printf 'Confirm (y/n): '
IFS= read -r confirm
{
  printf 'POOL=%s\n' "$pool"
  printf 'ACTION=%s\n' "$action"
  printf 'CONFIRM=%s\n' "$confirm"
} >> "$ALLOC_TRACE"
printf 'Action %s applied to %s.\n' "$action" "$pool"
'''
    with open(allocator, "w") as handle:
        handle.write(replacement)
    os.chmod(allocator, 0o755)
    try:
        yield
    finally:
        with open(allocator, "wb") as handle:
            handle.write(original)
        os.chmod(allocator, original_mode)


def test_files_exist_and_executable():
    for path in ("/home/user/auto_expand.exp", "/home/user/pipeline.sh"):
        assert os.path.isfile(path), f"Required script not found at {path}"
        assert os.access(path, os.X_OK), f"Script at {path} is not executable"


def test_health_endpoint_empty(go_server):
    clear_pools()
    assert health() == (200, "OK")


def test_proxy_endpoint(go_server):
    request = urllib.request.Request("http://localhost:8080/backend")
    try:
        urllib.request.urlopen(request, timeout=3)
        pytest.fail("Expected the proxy to a dead backend to fail")
    except urllib.error.HTTPError as error:
        assert error.code in (502, 503), f"Expected 502 or 503, got {error.code}"


def test_proxy_forwards_to_live_backend(go_server):
    token = "backend-" + "".join(random.choice(string.ascii_letters) for _ in range(20))

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = (token + ":" + self.path).encode()
            self.send_response(201)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    backend = ReusableTCPServer(("127.0.0.1", 9090), Handler)
    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()
    try:
        with urllib.request.urlopen("http://localhost:8080/backend", timeout=3) as response:
            assert response.status == 201
            assert response.read().decode() == token + ":/backend"
    finally:
        backend.shutdown()
        backend.server_close()
        thread.join(timeout=3)


def test_recursive_aggregate_and_boundary(go_server):
    clear_pools()
    suffix = "".join(random.choice(string.ascii_lowercase) for _ in range(12))
    first = random.randint(1_000_000, 4_000_000)
    second = random.randint(1_000_000, 4_000_000)
    third = LIMIT - first - second
    make_file("pool1", f"nested/{suffix}/first.bin", first)
    make_file("pool1", f"nested/{suffix}/deeper/second.bin", second)
    make_file("pool1", f"third-{suffix}.bin", third)
    assert health() == (200, "OK"), "Exactly 10 MB must not be treated as exceeding the limit"

    make_file("pool1", f"nested/{suffix}/one-more-byte", 1)
    assert health() == (503, "UNHEALTHY: pool1")


def test_varied_pool2_files(go_server):
    clear_pools()
    suffix = "".join(random.choice(string.ascii_lowercase) for _ in range(10))
    sizes = [2_345_671, 3_456_789, 4_683_000]
    assert sum(sizes) > LIMIT
    for index, size in enumerate(sizes):
        make_file("pool2", f"level-{suffix}/{index}/chunk-{suffix}-{index}", size)
    assert health() == (503, "UNHEALTHY: pool2")


def test_both_pools_under_and_both_over(go_server):
    clear_pools()
    make_file("pool1", "under/a", LIMIT - 123)
    make_file("pool2", "under/b", LIMIT - 456)
    assert health() == (200, "OK")

    clear_pools()
    make_file("pool1", "over/a", LIMIT + 17)
    make_file("pool2", "over/b", LIMIT + 29)
    status, body = health()
    assert status == 503
    assert body in ("UNHEALTHY: pool1", "UNHEALTHY: pool2")


def test_original_named_pool1_case(go_server):
    clear_pools()
    make_file("pool1", "largefile", 15 * 1024 * 1024)
    assert health() == (503, "UNHEALTHY: pool1")


def test_expect_script_interacts_with_allocator(instrumented_allocator):
    pool = "pool-" + "".join(random.choice(string.ascii_letters) for _ in range(18))
    trace = "/tmp/allocator-direct-trace"
    if os.path.exists(trace):
        os.unlink(trace)
    environment = os.environ.copy()
    environment["ALLOC_TRACE"] = trace
    result = subprocess.run(
        ["/home/user/auto_expand.exp", pool],
        capture_output=True,
        text=True,
        timeout=10,
        env=environment,
    )
    assert result.returncode == 0, result.stderr
    with open(trace) as handle:
        assert handle.read().splitlines() == [f"POOL={pool}", "ACTION=expand", "CONFIRM=y"]

    for args in ([], ["pool1", "extra"]):
        result = subprocess.run(
            ["/home/user/auto_expand.exp", *args],
            capture_output=True,
            text=True,
            timeout=10,
            env=environment,
        )
        assert result.returncode != 0, "Expect script must accept exactly one argument"


def run_pipeline(trace):
    environment = os.environ.copy()
    environment["ALLOC_TRACE"] = trace
    return subprocess.run(
        ["/home/user/pipeline.sh"],
        capture_output=True,
        text=True,
        timeout=15,
        env=environment,
    )


def test_pipeline_ok_does_nothing(go_server, instrumented_allocator):
    clear_pools()
    trace = "/tmp/allocator-ok-trace"
    log = "/home/user/capacity.log"
    for path in (trace, log):
        if os.path.exists(path):
            os.unlink(path)
    with open(log, "w") as handle:
        handle.write("existing marker\n")
    result = run_pipeline(trace)
    assert result.returncode == 0, result.stderr
    assert not os.path.exists(trace), "Allocator was invoked for a healthy response"
    with open(log) as handle:
        assert handle.read() == "existing marker\n", "Healthy pipeline modified capacity.log"


@pytest.mark.parametrize("pool", ["pool1", "pool2"])
def test_pipeline_expands_reported_pool(go_server, instrumented_allocator, pool):
    clear_pools()
    make_file(pool, f"random/deep/chunk-{random.randrange(1 << 30)}", LIMIT + random.randint(1, 5000))
    trace = f"/tmp/allocator-pipeline-{pool}-trace"
    log = "/home/user/capacity.log"
    for path in (trace, log):
        if os.path.exists(path):
            os.unlink(path)
    with open(log, "w") as handle:
        handle.write("existing marker\n")

    result = run_pipeline(trace)
    assert result.returncode == 0, f"Pipeline failed: {result.stderr}"
    with open(trace) as handle:
        assert handle.read().splitlines() == [f"POOL={pool}", "ACTION=expand", "CONFIRM=y"]
    with open(log) as handle:
        assert handle.read().splitlines() == ["existing marker", f"Expanded capacity for {pool}"]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
