#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.machinery
import json
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import uuid

import pytest
import redis
import requests

APP = "/app"
API_PROCESS = None
WORKER_PROCESS = None
LOG_HANDLES = []


def terminate_matching(needles):
    me = os.getpid()
    for entry in pathlib.Path("/proc").iterdir():
        if not entry.name.isdigit() or int(entry.name) == me:
            continue
        try:
            cmdline = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="ignore")
            if any(needle in cmdline for needle in needles):
                os.kill(int(entry.name), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.5)


def ensure_redis():
    client = redis.Redis(host="localhost", port=6379, db=0)
    try:
        client.ping()
    except Exception:
        subprocess.run(["redis-server", "--daemonize", "yes"], check=True)
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                client.ping()
                break
            except Exception:
                time.sleep(0.05)
        else:
            pytest.fail("Redis did not start")
    return client


def start_api():
    global API_PROCESS
    terminate_matching(["uvicorn", "/app/api.py"])
    env = os.environ.copy()
    env["PYTHONPATH"] = APP
    log = open("/tmp/verifier-api.log", "ab", buffering=0)
    LOG_HANDLES.append(log)
    API_PROCESS = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "api:app", "--host", "127.0.0.1", "--port", "8000", "--log-level", "warning"],
        cwd="/tmp", env=env, stdout=log, stderr=log,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        if API_PROCESS.poll() is not None:
            pytest.fail("FastAPI service exited during startup")
        try:
            response = requests.get("http://127.0.0.1:8000/docs", timeout=0.5)
            if response.status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(0.05)
    pytest.fail("FastAPI service did not become ready")


def start_worker(extra_pythonpath=None, extra_env=None):
    global WORKER_PROCESS
    if WORKER_PROCESS is not None and WORKER_PROCESS.poll() is None:
        WORKER_PROCESS.terminate()
        try:
            WORKER_PROCESS.wait(timeout=3)
        except subprocess.TimeoutExpired:
            WORKER_PROCESS.kill()
    terminate_matching(["/app/worker.py", "import worker; worker.main()"])
    env = os.environ.copy()
    paths = []
    if extra_pythonpath:
        paths.append(extra_pythonpath)
    paths.append(APP)
    env["PYTHONPATH"] = os.pathsep.join(paths)
    if extra_env:
        env.update(extra_env)
    log = open("/tmp/verifier-worker.log", "ab", buffering=0)
    LOG_HANDLES.append(log)
    WORKER_PROCESS = subprocess.Popen(
        [sys.executable, "-c", "import worker; worker.main()"],
        cwd="/tmp", env=env, stdout=log, stderr=log,
    )
    time.sleep(0.3)
    assert WORKER_PROCESS.poll() is None, "Worker exited during startup"


def wait_for_value(client, key, expected, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = int(client.get(key) or 0)
        if value >= expected:
            return value
        time.sleep(0.01)
    return int(client.get(key) or 0)


def test_rust_ecc_installed():
    """Verify that the rust_ecc module has been built and installed into the Python environment."""
    try:
        import rust_ecc
    except ImportError:
        pytest.fail("The 'rust_ecc' module is not installed or cannot be imported. Ensure maturin build and install succeeded.")

    module_path = os.path.realpath(rust_ecc.__file__)
    suffixes = tuple(importlib.machinery.EXTENSION_SUFFIXES)
    assert module_path.endswith(suffixes), f"rust_ecc is not a native Python extension: {module_path}"
    assert callable(getattr(rust_ecc, "compute_checksum", None)), "rust_ecc.compute_checksum is missing"


def test_checksum_correctness():
    import rust_ecc

    cases = [
        [],
        [1, 2, 3, 4, 5],
        [-9, 4, 12, -3],
        [0, 0, 0],
        list(range(-30, 31)),
        [123456, -65432, 77],
    ]
    for values in cases:
        expected = sum(values) * 100
        actual = rust_ecc.compute_checksum(values)
        assert type(actual) is int
        assert actual == expected, f"Incorrect checksum for {values}: got {actual}, expected {expected}"


def test_rust_project_builds_with_pyo3():
    cargo = pathlib.Path("/app/rust_ecc/Cargo.toml")
    source = pathlib.Path("/app/rust_ecc/src/lib.rs")
    assert cargo.is_file(), "Cargo.toml is missing"
    assert source.is_file(), "src/lib.rs is missing"
    cargo_text = cargo.read_text()
    source_text = source.read_text()
    assert 'crate-type = ["cdylib"]' in cargo_text.replace("'", '"'), "Rust library is not configured as a cdylib"
    assert "pyo3" in cargo_text.lower(), "PyO3 dependency is missing"
    assert "extension-module" in cargo_text, "PyO3 extension-module feature is not configured"
    assert "#[pymodule]" in source_text and "#[pyfunction]" in source_text, "PyO3 module/function declarations are missing"
    result = subprocess.run(
        ["cargo", "check", "--manifest-path", str(cargo)],
        capture_output=True, text=True, timeout=180,
    )
    assert result.returncode == 0, f"Rust project does not compile.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def test_worker_uses_rust_ecc():
    """Verify that the worker script has been updated to use the rust_ecc module."""
    worker_path = "/app/worker.py"
    assert os.path.isfile(worker_path), f"{worker_path} is missing."
    with open(worker_path, "r") as f:
        content = f.read()
    assert "rust_ecc" in content, "The worker script does not appear to import or use 'rust_ecc'."

    tree = ast.parse(content, worker_path)
    imports_module = any(
        isinstance(node, ast.Import) and any(alias.name == "rust_ecc" for alias in node.names)
        for node in ast.walk(tree)
    )
    calls_function = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == "rust_ecc"
        and node.func.attr == "compute_checksum"
        for node in ast.walk(tree)
    )
    assert imports_module, "worker.py must import the rust_ecc module"
    assert calls_function, "worker.py must call rust_ecc.compute_checksum(data)"
    assert "utils.naive_checksum" not in content, "worker.py still imports the naive checksum implementation"


def test_services_really_communicate_and_worker_calls_checksum():
    client = ensure_redis()
    client.flushdb()
    start_api()

    shim_dir = tempfile.mkdtemp(prefix="ecc_probe_")
    marker = os.path.join(shim_dir, "calls.jsonl")
    pathlib.Path(shim_dir, "rust_ecc.py").write_text(
        "import json, os\n"
        "def compute_checksum(data):\n"
        "    with open(os.environ['ECC_MARKER'], 'a') as f:\n"
        "        f.write(json.dumps(data) + '\\n')\n"
        "    return sum(data) * 100\n"
    )
    start_worker(shim_dir, {"ECC_MARKER": marker})

    payload = [17, -2, 99, int(uuid.uuid4().int % 100000)]
    response = requests.post("http://127.0.0.1:8000/process", json=payload, timeout=2)
    assert response.status_code == 200
    assert response.json() == {"status": "queued"}
    assert wait_for_value(client, "processed_count", 1, timeout=5) == 1

    deadline = time.time() + 3
    while time.time() < deadline and not os.path.exists(marker):
        time.sleep(0.01)
    assert os.path.isfile(marker), "The worker did not invoke rust_ecc.compute_checksum"
    calls = [json.loads(line) for line in pathlib.Path(marker).read_text().splitlines() if line]
    assert calls == [payload], f"Worker passed incorrect data to rust_ecc: {calls}"
    assert client.llen("queue") == 0, "Worker did not consume the queued request"


def test_independent_end_to_end_performance():
    client = ensure_redis()
    start_worker()

    probe = subprocess.run(
        [sys.executable, "-c", "import rust_ecc; print(rust_ecc.__file__)"],
        cwd="/tmp", env={**os.environ, "PYTHONPATH": APP},
        capture_output=True, text=True, timeout=10,
    )
    assert probe.returncode == 0, probe.stderr
    assert probe.stdout.strip().endswith(tuple(importlib.machinery.EXTENSION_SUFFIXES)), "Worker environment does not resolve rust_ecc to a native extension"

    client.flushdb()
    total = 1000
    start = time.time()
    for i in range(total):
        payload = [1, 2, 3, 4, 5, i % 13]
        response = requests.post("http://127.0.0.1:8000/process", json=payload, timeout=2)
        assert response.status_code == 200
        assert response.json() == {"status": "queued"}

    deadline = start + 10
    count = 0
    while time.time() < deadline:
        count = int(client.get("processed_count") or 0)
        if count >= total:
            break
        assert WORKER_PROCESS.poll() is None, "Worker exited during benchmark"
        assert API_PROCESS.poll() is None, "API exited during benchmark"
        time.sleep(0.01)

    duration = time.time() - start
    count = int(client.get("processed_count") or 0)
    assert count == total, f"Expected exactly {total} processed requests, got {count}"
    assert client.llen("queue") == 0, "Requests remain unprocessed in Redis"
    measured_rps = count / duration if duration > 0 else 0
    assert measured_rps >= 800, f"Independent performance threshold not met. Got {measured_rps} requests/second, expected >= 800."


def test_benchmark_performance():
    """Run the benchmark and verify that the throughput meets the threshold."""
    benchmark_path = "/app/benchmark.py"
    result_path = "/tmp/result.json"

    assert os.path.isfile(benchmark_path), f"{benchmark_path} is missing."
    if os.path.exists(result_path):
        os.unlink(result_path)

    cmd = [sys.executable, benchmark_path, "--json-output", result_path]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=20)

    assert result.returncode == 0, f"Benchmark script failed to execute.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.isfile(result_path), f"Benchmark script did not create the expected output file at {result_path}."

    with open(result_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse JSON from {result_path}.")

    assert "requests_per_second" in data, f"'requests_per_second' key missing in {result_path}."
    metric = data["requests_per_second"]
    threshold = 800
    assert metric >= threshold, f"Performance threshold not met. Got {metric} requests_per_second, expected >= {threshold}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
