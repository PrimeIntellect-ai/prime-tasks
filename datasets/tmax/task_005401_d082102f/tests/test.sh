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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import os
import random
import socket
import subprocess
import tempfile
from pathlib import Path

import pytest
import requests

PID_FILE = "/app/service.pid"
HTTP_URL = "http://127.0.0.1:8080/process"


def read_service_pid():
    assert os.path.exists(PID_FILE), f"{PID_FILE} does not exist. The service PID must be written here."
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"{PID_FILE} does not contain a valid numeric PID. Found: {pid_str}"
    return int(pid_str)


def test_service_pid_exists_and_running():
    pid = read_service_pid()
    assert os.path.exists(f"/proc/{pid}"), f"Process with PID {pid} is not running."

    service_path = Path("/app/compute_node.py")
    assert service_path.is_file(), f"Required service script {service_path} is missing."
    cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\x00", b" ").decode(errors="replace")
    assert "compute_node" in cmdline, f"PID {pid} does not appear to be running the compute_node service: {cmdline!r}"


def post_and_check(value):
    try:
        response = requests.post(HTTP_URL, json={"input": value}, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP endpoint at {HTTP_URL}. Error: {e}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")

    assert data.get("status") == "success", f"Expected 'status' to be 'success', got {data.get('status')}"
    assert data.get("output") == value * value, (
        f"Expected output {value * value} for input {value}, got {data.get('output')}"
    )


def test_http_endpoint():
    # Preserve the original fixed assertion, then exercise unpredictable inputs.
    post_and_check(10)
    rng = random.SystemRandom()
    values = set()
    while len(values) < 7:
        value = rng.randrange(-1000, 1001)
        if value != 10:
            values.add(value)
    for value in values:
        post_and_check(value)


def recv_exact(sock, size):
    chunks = []
    remaining = size
    while remaining:
        chunk = sock.recv(remaining)
        assert chunk, "TCP service closed the connection before sending a complete response."
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def test_tcp_endpoint():
    host = "127.0.0.1"
    port = 8081
    try:
        s = socket.create_connection((host, port), timeout=5)
    except Exception as e:
        pytest.fail(f"Failed to connect to TCP endpoint at {host}:{port}. Error: {e}")

    try:
        s.settimeout(5)
        # Multiple requests on one connection verify that it remains open.
        for _ in range(4):
            s.sendall(b"HEARTBEAT\n")
            response = recv_exact(s, len(b"ALIVE\n"))
            assert response == b"ALIVE\n", f"Expected response b'ALIVE\\n', got {response!r}"
    except Exception as e:
        pytest.fail(f"Failed to communicate repeatedly with TCP endpoint: {e}")
    finally:
        s.close()


def test_installed_fastalgo_extension():
    import fastalgo

    module_path = os.path.realpath(fastalgo.__file__)
    assert os.path.isfile(module_path), f"Imported fastalgo artifact is missing: {module_path}"
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        f"fastalgo is not an installed native Python extension: {module_path}"
    )

    rng = random.SystemRandom()
    for _ in range(6):
        value = rng.randrange(-1000, 1001)
        assert fastalgo.process_data(value) == value * value

    dynamic = subprocess.check_output(["readelf", "-d", module_path], text=True)
    assert "libalgo.so" in dynamic, f"Installed extension is not dynamically linked to libalgo.so:\n{dynamic}"


def listening_socket_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table, "r") as f:
            next(f)
            for line in f:
                fields = line.split()
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
                state = fields[3]
                if local_port == port and state == "0A":
                    result.add(fields[9])
    return result


def test_service_process_owns_ports_and_loads_extension():
    import fastalgo

    pid = read_service_pid()
    owned = set()
    for fd in Path(f"/proc/{pid}/fd").iterdir():
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            owned.add(target[len("socket:["):-1])

    for port in (8080, 8081):
        listeners = listening_socket_inodes(port)
        assert listeners, f"No listening socket found on port {port}."
        assert listeners & owned, f"PID {pid} does not own the listening socket on port {port}."

    maps = Path(f"/proc/{pid}/maps").read_text(errors="replace")
    extension_path = os.path.realpath(fastalgo.__file__)
    assert extension_path in maps, f"Service PID {pid} has not loaded the installed fastalgo extension."
    assert "/app/proprietary/libalgo.so" in maps, f"Service PID {pid} has not loaded /app/proprietary/libalgo.so."


def test_cmake_configuration_fixed_and_buildable():
    cmake_path = "/app/fastalgo/CMakeLists.txt"
    assert os.path.exists(cmake_path), f"CMakeLists.txt missing at {cmake_path}"
    with open(cmake_path, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "target_link_libraries" in content, (
        "CMakeLists.txt is missing the 'target_link_libraries' directive to link libalgo.so."
    )

    # Configure and build from scratch so comments or stale artifacts cannot satisfy the check.
    with tempfile.TemporaryDirectory() as tmp:
        build_dir = os.path.join(tmp, "build")
        output_dir = os.path.join(tmp, "output")
        subprocess.check_call([
            "cmake", "-S", "/app/fastalgo", "-B", build_dir,
            f"-DCMAKE_LIBRARY_OUTPUT_DIRECTORY={output_dir}",
        ])
        subprocess.check_call(["cmake", "--build", build_dir, "--clean-first"])

        candidates = list(Path(output_dir).rglob("fastalgo*.so"))
        assert candidates, "Fresh CMake build did not produce the fastalgo extension."
        artifact = str(candidates[0].resolve())
        dynamic = subprocess.check_output(["readelf", "-d", artifact], text=True)
        assert "libalgo.so" in dynamic, f"Freshly built extension is not linked to libalgo.so:\n{dynamic}"

        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = "/app/proprietary" + (
            ":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else ""
        )
        code = (
            "import importlib.util,sys; "
            "p=sys.argv[1]; s=importlib.util.spec_from_file_location('fastalgo',p); "
            "m=importlib.util.module_from_spec(s); s.loader.exec_module(m); "
            "assert m.process_data(-37)==1369; assert m.process_data(123)==15129"
        )
        subprocess.check_call(["python3", "-c", code, artifact], env=env)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
