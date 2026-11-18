#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier
export PATH="/usr/local/go/bin:$PATH"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import glob
import os
import random
import signal
import string
import subprocess
import sys
import tempfile
import time
import uuid

import grpc
import pytest
import redis
import requests

APP_DIR = "/home/user/app"
GO_DIR = os.path.join(APP_DIR, "go_src")
C_DIR = os.path.join(APP_DIR, "c_src")
URL = "http://127.0.0.1:8080/process"

sys.path.insert(0, os.path.join(APP_DIR, "python_gateway"))
import processor_pb2
import processor_pb2_grpc


def listener_pids(port):
    wanted = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    cols = line.split()
                    if len(cols) >= 10 and cols[1].split(":")[-1] == wanted and cols[3] == "0A":
                        inodes.add(cols[9])
        except FileNotFoundError:
            pass

    result = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(os.path.join(procdir, "fd")):
                try:
                    target = os.readlink(os.path.join(procdir, "fd", fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(pid)
                    break
        except OSError:
            pass
    return result


def stop_existing_services():
    pids = set()
    for port in (8080, 50051, 6379):
        pids.update(listener_pids(port))
    pids.discard(os.getpid())
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while time.time() < deadline and any(listener_pids(p) for p in (8080, 50051, 6379)):
        time.sleep(0.1)
    for port in (8080, 50051, 6379):
        for pid in listener_pids(port):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def wait_near_start_of_second():
    deadline = time.time() + 3
    while time.time() < deadline:
        if time.time() % 1 < 0.12:
            return
        time.sleep(0.005)
    pytest.fail("Could not synchronize rate-limit test to a fixed-window boundary")


@pytest.fixture(scope="session", autouse=True)
def setup_services():
    stop_existing_services()
    start_script = os.path.join(APP_DIR, "start.sh")
    assert os.path.isfile(start_script), "start.sh is missing"
    assert os.access(start_script, os.X_OK), "start.sh is not executable"

    with tempfile.TemporaryFile(mode="w+") as output:
        proc = subprocess.Popen([start_script], cwd=APP_DIR, stdout=output, stderr=subprocess.STDOUT, text=True)
        try:
            rc = proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
            pytest.fail("start.sh did not exit after launching the background services")
        output.seek(0)
        log = output.read()
    assert rc == 0, f"start.sh failed with exit code {rc}. Output:\n{log}"

    for _ in range(60):
        try:
            res = requests.post(URL, json={"client_id": "warmup", "input_data": "test"}, timeout=1)
            if res.status_code in (200, 429, 500):
                break
        except requests.RequestException:
            pass
        time.sleep(0.25)
    else:
        pytest.fail("Python gateway did not become responsive on 127.0.0.1:8080")

    assert listener_pids(6379), "Redis is not listening on 127.0.0.1:6379"
    assert listener_pids(50051), "The gRPC service is not listening on 127.0.0.1:50051"
    assert listener_pids(8080), "The HTTP gateway is not listening on 127.0.0.1:8080"

    yield


def test_required_sources_and_builds():
    cmake = subprocess.run(
        ["cmake", "-S", C_DIR, "-B", "/tmp/verifier-cbuild"],
        capture_output=True, text=True
    )
    assert cmake.returncode == 0, f"CMake configuration failed:\n{cmake.stdout}\n{cmake.stderr}"
    build = subprocess.run(
        ["cmake", "--build", "/tmp/verifier-cbuild"],
        capture_output=True, text=True
    )
    assert build.returncode == 0, f"C library build failed:\n{build.stdout}\n{build.stderr}"
    libs = glob.glob("/tmp/verifier-cbuild/**/libprocessor.so", recursive=True)
    assert libs, "CMake did not produce libprocessor.so"

    pb_files = glob.glob(os.path.join(GO_DIR, "**", "*.pb.go"), recursive=True)
    grpc_files = glob.glob(os.path.join(GO_DIR, "**", "*_grpc.pb.go"), recursive=True)
    assert pb_files, "Generated Go protobuf bindings are missing"
    assert grpc_files, "Generated Go gRPC bindings are missing"

    go_files = [p for p in glob.glob(os.path.join(GO_DIR, "**", "*.go"), recursive=True)
                if not p.endswith(".pb.go")]
    assert go_files, "Go service source is missing"
    source = "\n".join(open(p, errors="replace").read() for p in go_files)
    assert "C.process_data" in source, "Go service does not call process_data through cgo"
    assert "C.free" in source, "Go service does not free the heap string returned by process_data"
    assert "grpc.NewServer" in source, "Go service does not create a gRPC server"
    assert "RegisterProcessorServiceServer" in source, "ProcessorService is not registered with gRPC"
    assert "rate:" in source, "Go service source does not construct the required Redis rate key"

    env = os.environ.copy()
    env["CGO_ENABLED"] = "1"
    gobuild = subprocess.run(
        ["go", "build", "-o", "/tmp/verifier-processor-service", "."],
        cwd=GO_DIR, env=env, capture_output=True, text=True, timeout=120
    )
    assert gobuild.returncode == 0, f"go build failed:\n{gobuild.stdout}\n{gobuild.stderr}"
    assert os.path.isfile("/tmp/verifier-processor-service")
    dynamic = subprocess.run(
        ["readelf", "-d", "/tmp/verifier-processor-service"],
        capture_output=True, text=True
    )
    assert dynamic.returncode == 0, "Built Go service is not a valid executable"
    assert "libprocessor.so" in dynamic.stdout, "Built Go service is not dynamically linked to libprocessor.so"


def test_running_service_is_go_and_uses_shared_library():
    # Make at least one call so all runtime mappings are established.
    value = "mapcheck-" + uuid.uuid4().hex
    with grpc.insecure_channel("127.0.0.1:50051") as channel:
        stub = processor_pb2_grpc.ProcessorServiceStub(channel)
        resp = stub.Process(processor_pb2.ProcessRequest(client_id=uuid.uuid4().hex, input_data=value), timeout=5)
        assert resp.output_data == "PROCESSED:" + value

    pids = listener_pids(50051)
    assert len(pids) == 1, f"Expected one gRPC listener, found PIDs {pids}"
    pid = next(iter(pids))
    exe = os.path.realpath(f"/proc/{pid}/exe")
    goversion = subprocess.run(["go", "version", "-m", exe], capture_output=True, text=True)
    assert goversion.returncode == 0 and "go1." in goversion.stdout, "Port 50051 is not served by a Go binary"
    with open(f"/proc/{pid}/maps", errors="replace") as f:
        maps = f.read()
    assert "libprocessor.so" in maps, "Running Go service has not loaded libprocessor.so"

    gateway_pids = listener_pids(8080)
    assert gateway_pids, "Gateway process is missing"
    cmdlines = []
    for gateway_pid in gateway_pids:
        try:
            cmdlines.append(open(f"/proc/{gateway_pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace"))
        except OSError:
            pass
    assert any("python_gateway/app.py" in c or ("app.py" in c and "python" in c.lower()) for c in cmdlines), \
        f"Port 8080 is not being served by the provided Python gateway: {cmdlines}"


def test_basic_processing():
    payload = {"client_id": "tester", "input_data": "world"}
    response = requests.post(URL, json=payload, timeout=5)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "output_data" in data, f"Response JSON missing 'output_data': {data}"
    assert data["output_data"] == "PROCESSED:world", f"Unexpected output_data: {data['output_data']}"


def test_randomized_http_and_direct_grpc_processing():
    alphabet = string.ascii_letters + string.digits + "-_:."
    values = ["".join(random.SystemRandom().choice(alphabet) for _ in range(random.randint(20, 70))) for _ in range(5)]

    for value in values[:3]:
        response = requests.post(URL, json={"client_id": uuid.uuid4().hex, "input_data": value}, timeout=5)
        assert response.status_code == 200, response.text
        assert response.json() == {"output_data": "PROCESSED:" + value}

    with grpc.insecure_channel("127.0.0.1:50051") as channel:
        stub = processor_pb2_grpc.ProcessorServiceStub(channel)
        for value in values[3:]:
            response = stub.Process(
                processor_pb2.ProcessRequest(client_id=uuid.uuid4().hex, input_data=value), timeout=5
            )
            assert response.output_data == "PROCESSED:" + value


def test_redis_fixed_window_key_and_grpc_status():
    r = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    assert r.ping()
    r.flushdb()
    client_id = "grpc-rate-" + uuid.uuid4().hex
    wait_near_start_of_second()
    second = int(time.time())

    with grpc.insecure_channel("127.0.0.1:50051") as channel:
        stub = processor_pb2_grpc.ProcessorServiceStub(channel)
        for i in range(3):
            response = stub.Process(
                processor_pb2.ProcessRequest(client_id=client_id, input_data=f"value-{i}"), timeout=5
            )
            assert response.output_data == f"PROCESSED:value-{i}"
        with pytest.raises(grpc.RpcError) as exc:
            stub.Process(processor_pb2.ProcessRequest(client_id=client_id, input_data="blocked"), timeout=5)
        assert exc.value.code() == grpc.StatusCode.RESOURCE_EXHAUSTED

    assert int(time.time()) == second, "Rate-limit requests crossed a one-second fixed window"
    expected_key = f"rate:{client_id}:{second}"
    keys = list(r.scan_iter(f"rate:{client_id}:*"))
    assert keys == [expected_key], f"Expected Redis key {expected_key}, found {keys}"
    assert int(r.get(expected_key)) >= 3, "Redis counter was not incremented for the requests"

    other = "other-" + uuid.uuid4().hex
    with grpc.insecure_channel("127.0.0.1:50051") as channel:
        stub = processor_pb2_grpc.ProcessorServiceStub(channel)
        response = stub.Process(processor_pb2.ProcessRequest(client_id=other, input_data="independent"), timeout=5)
        assert response.output_data == "PROCESSED:independent"


def test_rate_limiting():
    r = redis.Redis(host="127.0.0.1", port=6379)
    r.flushdb()
    client_id = "rate_limit_tester"
    payload = {"client_id": client_id, "input_data": "world"}
    wait_near_start_of_second()
    second = int(time.time())

    def make_request():
        return requests.post(URL, json=payload, timeout=5)

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        responses = [f.result() for f in [executor.submit(make_request) for _ in range(5)]]

    status_codes = [r.status_code for r in responses]
    successes = status_codes.count(200)
    failures = len([c for c in status_codes if c != 200])
    assert successes == 3, f"Expected exactly 3 successful requests, got {successes}. Status codes: {status_codes}"
    assert failures == 2, f"Expected exactly 2 rate-limited requests, got {failures}. Status codes: {status_codes}"
    for code in status_codes:
        if code != 200:
            assert code in (429, 500), f"Expected rate limit error code to be 429 (or 500), got {code}"
    assert status_codes.count(429) == 2, f"ResourceExhausted must be mapped to HTTP 429, got {status_codes}"
    assert int(time.time()) == second, "Concurrent requests crossed a one-second fixed window"
    for response in responses:
        if response.status_code == 200:
            assert response.json().get("output_data") == "PROCESSED:world"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
