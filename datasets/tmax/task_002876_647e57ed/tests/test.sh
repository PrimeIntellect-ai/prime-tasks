#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import time
import uuid

import pytest

sys.path.insert(0, "/home/user")

SO_PATH = "/home/user/libmobilecore/build/libmobilecore.so"
SERVER_PATH = "/home/user/server.py"
DIFF_PATH = "/home/user/large_build.diff"
SUMMARY_PATH = "/home/user/diff_summary.json"
AGENT_PARSER = "/home/user/diff_parser.py"
PORT = 50051
RATE_LIMIT = 120


def reference_parse(path):
    with open(path, "r") as f:
        lines = f.readlines()

    summary = {}
    current_file = None
    for line in lines:
        if line.startswith("+++ "):
            current_file = line[4:].strip()
            if current_file not in summary:
                summary[current_file] = {"additions": 0, "deletions": 0}
        elif line.startswith("+") and not line.startswith("+++"):
            if current_file:
                summary[current_file]["additions"] = summary[current_file].get("additions", 0) + 1
        elif line.startswith("-") and not line.startswith("---"):
            if current_file:
                summary[current_file]["deletions"] = summary[current_file].get("deletions", 0) + 1
    return summary


def stop_servers():
    subprocess.run(["pkill", "-f", SERVER_PATH], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.4)


def start_server():
    proc = subprocess.Popen(
        [sys.executable, SERVER_PATH],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    import grpc
    try:
        grpc.channel_ready_future(grpc.insecure_channel(f"localhost:{PORT}")).result(timeout=8)
    except Exception:
        proc.terminate()
        proc.wait(timeout=5)
        pytest.fail(f"Server did not become ready on port {PORT}")
    return proc


def test_shared_library_compiled_and_abi_fixed():
    assert os.path.isfile(SO_PATH), f"Compiled shared library not found at {SO_PATH}"

    header_path = "/home/user/libmobilecore/core.h"
    with open(header_path, "r") as f:
        header = f.read()
    match = re.search(r"struct\s+CacheData\s*\{(?P<body>.*?)\};", header, re.S)
    assert match, "CacheData declaration is missing from core.h"
    body = match.group("body")
    assert re.search(r"\bint\s+value\s*;", body), "Patched CacheData.value field is missing"
    assert re.search(r"\bchar\s+type\s*;", body), "CacheData.type field is missing"
    assert body.index("int value") < body.index("char type"), "fix_abi.patch was not applied: value must precede type"

    lib = ctypes.CDLL(SO_PATH)
    fn = lib.process_cache_key
    fn.argtypes = [ctypes.c_char_p]
    fn.restype = ctypes.c_int
    probe = ("cache-" + uuid.uuid4().hex).encode()
    assert fn(probe) == len(probe), "Compiled process_cache_key does not implement the supplied library source"
    assert fn(None) == 0


def test_grpc_service_uses_library_and_rate_limit():
    try:
        import grpc
        import build_cache_pb2
        import build_cache_pb2_grpc
    except ImportError as e:
        pytest.fail(f"Failed to import gRPC generated files: {e}. Ensure they are compiled in /home/user.")

    assert os.path.isfile(SERVER_PATH), f"Server implementation missing at {SERVER_PATH}"
    stop_servers()

    # Temporarily instrument the required library path. A request must reach
    # process_cache_key, proving the service actually loads and calls the C ABI.
    token = uuid.uuid4().hex
    marker = f"/tmp/mobilecore_marker_{uuid.uuid4().hex}"
    backup = f"/tmp/libmobilecore_{uuid.uuid4().hex}.so"
    source = f"/tmp/mobilecore_probe_{uuid.uuid4().hex}.cpp"
    shutil.copy2(SO_PATH, backup)
    with open(source, "w") as f:
        f.write(r'''#include <cstdio>
#include <cstring>
extern "C" int process_cache_key(const char* key) {
    if (!key) return 0;
    FILE* out = std::fopen("''' + marker + r'''", "a");
    if (out) { std::fprintf(out, "%s\n", key); std::fclose(out); }
    return (int)std::strlen(key);
}
''')
    subprocess.run(["g++", "-shared", "-fPIC", "-O2", "-o", SO_PATH, source], check=True)

    probe_server = None
    try:
        probe_server = start_server()
        channel = grpc.insecure_channel(f"localhost:{PORT}")
        stub = build_cache_pb2_grpc.BuildCacheStub(channel)
        response = stub.CheckCache(build_cache_pb2.CacheRequest(key=token), timeout=3)
        assert response.hit is True
        deadline = time.time() + 2
        while time.time() < deadline and not os.path.exists(marker):
            time.sleep(0.05)
        assert os.path.isfile(marker), "The gRPC server did not call process_cache_key from libmobilecore.so"
        with open(marker, "r") as f:
            assert token in f.read(), "The server did not pass the request cache key to the C++ library"
    finally:
        if probe_server is not None:
            probe_server.terminate()
            try:
                probe_server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                probe_server.kill()
                probe_server.wait(timeout=5)
        shutil.move(backup, SO_PATH)
        for path in (source, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        stop_servers()

    # Start the submitted server against the submitted, restored library and
    # leave this instance running after verification.
    server = start_server()
    channel = grpc.insecure_channel(f"localhost:{PORT}")
    stub = build_cache_pb2_grpc.BuildCacheStub(channel)

    with pytest.raises(grpc.RpcError) as empty_error:
        stub.CheckCache(build_cache_pb2.CacheRequest(key=""), timeout=2)
    assert empty_error.value.code() == grpc.StatusCode.INVALID_ARGUMENT, "Empty cache keys must be rejected as invalid"

    success_count = 0
    exhausted_count = 0
    for i in range(125):
        request = build_cache_pb2.CacheRequest(key=f"test_key_{i}_{uuid.uuid4().hex}")
        try:
            stub.CheckCache(request, timeout=2)
            success_count += 1
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.RESOURCE_EXHAUSTED:
                exhausted_count += 1
            else:
                pytest.fail(f"Unexpected gRPC error: {e.code()} - {e.details()}")

    assert success_count == RATE_LIMIT, f"Expected exactly {RATE_LIMIT} successful requests, got {success_count}."
    assert exhausted_count == 5, f"Expected exactly 5 RESOURCE_EXHAUSTED failures, got {exhausted_count}."
    assert server.poll() is None, "The submitted gRPC server exited during testing"


def test_diff_parser_speedup_and_exact_output():
    assert os.path.isfile(AGENT_PARSER), f"Agent script missing at {AGENT_PARSER}"
    assert os.path.isfile(DIFF_PATH), f"Diff file missing at {DIFF_PATH}"

    original_backup = f"/tmp/original_diff_{uuid.uuid4().hex}"
    baseline_script = f"/tmp/diff_baseline_{uuid.uuid4().hex}.py"
    shutil.copy2(DIFF_PATH, original_backup)

    # Use a fresh, unpredictable workload so a precomputed summary cannot pass.
    prefix = uuid.uuid4().hex
    try:
        with open(DIFF_PATH, "w") as f:
            for i in range(2500):
                pairs = 80 + (i % 41)
                f.write(f"--- a/{prefix}/file_{i}.txt\n")
                f.write(f"+++ b/{prefix}/file_{i}.txt\n")
                for j in range(pairs):
                    f.write(f"+ added {prefix} line {i}-{j}\n")
                    f.write(f"- removed {prefix} line {i}-{j}\n")

        expected = reference_parse(DIFF_PATH)
        assert expected
        # The original parser retains the b/ prefix; preserving that behavior is required.
        assert all(name.startswith(f"b/{prefix}/") for name in expected)

        with open(baseline_script, "w") as f:
            f.write('''import json\n\ndef parse_diff(filename):\n    with open(filename, "r") as f:\n        lines = f.readlines()\n    summary = {}\n    current_file = None\n    for line in lines:\n        if line.startswith("+++ "):\n            current_file = line[4:].strip()\n            if current_file not in summary:\n                summary[current_file] = {"additions": 0, "deletions": 0}\n        elif line.startswith("+") and not line.startswith("+++"):\n            if current_file:\n                summary[current_file]["additions"] = summary[current_file].get("additions", 0) + 1\n        elif line.startswith("-") and not line.startswith("---"):\n            if current_file:\n                summary[current_file]["deletions"] = summary[current_file].get("deletions", 0) + 1\n    with open("/home/user/diff_summary.json", "w") as f:\n        json.dump(summary, f)\n\nparse_diff("/home/user/large_build.diff")\n''')

        def timed(script):
            started = time.perf_counter()
            subprocess.run([sys.executable, script], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return time.perf_counter() - started

        # Warm the filesystem cache equally, then compare median execution time.
        timed(baseline_script)
        timed(AGENT_PARSER)
        baseline_times = [timed(baseline_script) for _ in range(3)]
        agent_times = [timed(AGENT_PARSER) for _ in range(3)]
        baseline_time = statistics.median(baseline_times)
        agent_time = statistics.median(agent_times)
        speedup = baseline_time / agent_time
        assert speedup >= 2.5, (
            f"Speedup is {speedup:.2f}x, expected >= 2.5x. "
            f"Baseline: {baseline_time:.4f}s, Agent: {agent_time:.4f}s."
        )

        assert os.path.isfile(SUMMARY_PATH), f"Summary JSON missing at {SUMMARY_PATH}"
        with open(SUMMARY_PATH, "r") as f:
            try:
                agent_summary = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("Failed to parse diff_summary.json as valid JSON.")
        assert agent_summary == expected, "The generated diff_summary.json does not preserve the original parser output."
    finally:
        shutil.move(original_backup, DIFF_PATH)
        try:
            os.remove(baseline_script)
        except FileNotFoundError:
            pass

    # Also leave and validate the summary for the task's specified input.
    subprocess.run([sys.executable, AGENT_PARSER], check=True)
    expected_original = reference_parse(DIFF_PATH)
    with open(SUMMARY_PATH, "r") as f:
        agent_original = json.load(f)
    assert agent_original == expected_original, "diff_summary.json does not match the original parser's output format."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
