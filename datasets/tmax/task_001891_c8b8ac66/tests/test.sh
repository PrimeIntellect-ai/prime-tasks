#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import signal
import socket
import stat
import subprocess
import time

import pytest

EXPECTED_SOCKET = "/tmp/metrics_backend.sock"
EXPECTED_REPORT = [
    "[error] 2023/10/01 10:00:00 502 Bad Gateway - connection refused",
    "[error] 2023/10/01 10:02:00 502 Bad Gateway - socket not found",
]
SOURCE = "/home/user/backend/server.cpp"
BINARY = "/home/user/backend/server"


def server_pids():
    result = []
    expected = os.path.realpath(BINARY)
    for exe_file in glob.glob("/proc/[0-9]*/exe"):
        try:
            if os.path.realpath(exe_file) == expected:
                result.append(int(exe_file.split("/")[2]))
        except OSError:
            pass
    return result


def test_router_conf_updated():
    path = "/home/user/router.conf"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert EXPECTED_SOCKET in content, "router.conf does not point to the correct socket path: /tmp/metrics_backend.sock"

    sockets = re.findall(r"server\s+unix:([^;\s]+)\s*;", content)
    assert sockets == [EXPECTED_SOCKET], f"router.conf must route to exactly {EXPECTED_SOCKET}, found {sockets}"


def test_report_content_and_permissions():
    path = "/home/user/502_report.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    st = os.stat(path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"Permissions of {path} are {oct(perms)}, expected 0o400 strictly read-only for owner."

    with open(path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, f"Expected exactly 2 lines in {path}, found {len(lines)}."
    for line in lines:
        assert "502 Bad Gateway" in line, f"Line in report does not contain '502 Bad Gateway': {line}"
    assert lines == EXPECTED_REPORT, "502_report.txt is not the exact extraction of all 502 Bad Gateway entries from the supplied log."


def test_compiled_backend_is_running_and_reachable():
    assert os.path.isfile(BINARY), f"Compiled backend {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Compiled backend {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."

    pids = server_pids()
    assert pids, f"No running process is executing {BINARY}."
    assert stat.S_ISSOCK(os.stat(EXPECTED_SOCKET).st_mode), f"{EXPECTED_SOCKET} is not a UNIX socket."

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(2)
        client.connect(EXPECTED_SOCKET)
        client.sendall(b"metric\n")
        response = client.recv(16)
    assert response == b"OK", f"Running backend returned {response!r}, expected b'OK'."


def test_timezone_configured():
    path = SOURCE
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    if "Asia/Tokyo" in content:
        return

    found_tz = False
    for comm_file in glob.glob("/proc/[0-9]*/comm"):
        try:
            with open(comm_file, "r") as f:
                comm = f.read().strip()
            if comm == "server":
                pid = comm_file.split("/")[2]
                with open(f"/proc/{pid}/environ", "rb") as f:
                    env = f.read()
                if b"TZ=Asia/Tokyo" in env:
                    found_tz = True
                    break
        except Exception:
            continue

    assert found_tz, "Timezone 'Asia/Tokyo' not found in server.cpp or running 'server' process environment (TZ variable)."


def test_timezone_is_actually_configured():
    with open(SOURCE, "r") as f:
        content = f.read()

    configured_in_code = bool(
        re.search(r"setenv\s*\(\s*[\"']TZ[\"']\s*,\s*[\"']Asia/Tokyo[\"']", content)
        or re.search(r"putenv\s*\(\s*(?:const_cast<\s*char\s*\*\s*>\s*\()?\s*[\"']TZ=Asia/Tokyo[\"']", content)
    )

    configured_at_launch = False
    for pid in server_pids():
        try:
            with open(f"/proc/{pid}/environ", "rb") as f:
                entries = f.read().split(b"\0")
            if b"TZ=Asia/Tokyo" in entries:
                configured_at_launch = True
                break
        except OSError:
            pass

    assert configured_in_code or configured_at_launch, "Timezone must be configured in code with setenv/putenv or in the running backend's launch environment."


def test_benchmark_performance():
    script_path = "/home/user/benchmark.sh"
    assert os.path.isfile(script_path), f"Benchmark script {script_path} not found."

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Benchmark script failed with error: {result.stderr}"

    try:
        execution_time = float(result.stdout.strip())
    except ValueError:
        pytest.fail(f"Benchmark script did not output a valid float: {result.stdout}")

    threshold = 1.5
    assert execution_time <= threshold, f"Execution time {execution_time}s exceeds threshold of {threshold}s. The C++ backend is not optimized enough."


def test_source_compiles_and_passes_independent_load_test():
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    verified_binary = "/tmp/verified_metrics_server"
    compile_result = subprocess.run(
        ["g++", "-O3", SOURCE, "-o", verified_binary],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Backend failed to compile with g++ -O3:\n{compile_result.stderr}"
    with open(verified_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Freshly compiled backend is not an ELF executable."

    try:
        os.unlink(EXPECTED_SOCKET)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env.pop("TZ", None)
    proc = subprocess.Popen(
        [verified_binary],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"Freshly compiled backend exited with status {proc.returncode} before accepting connections.")
            try:
                if stat.S_ISSOCK(os.stat(EXPECTED_SOCKET).st_mode):
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
                        probe.settimeout(0.2)
                        probe.connect(EXPECTED_SOCKET)
                        probe.sendall(b"metric\n")
                        assert probe.recv(16) == b"OK"
                    break
            except (FileNotFoundError, ConnectionRefusedError, socket.timeout):
                time.sleep(0.02)
        else:
            pytest.fail(f"Freshly compiled backend did not bind and serve {EXPECTED_SOCKET}.")

        start = time.monotonic()
        for _ in range(10000):
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(2)
                client.connect(EXPECTED_SOCKET)
                client.sendall(b"metric\n")
                response = client.recv(16)
                assert response == b"OK", f"Backend returned {response!r} during load test."
        elapsed = time.monotonic() - start
        assert elapsed <= 1.5, f"Independent 10,000-metric load test took {elapsed:.6f}s, exceeding 1.5s."
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=2)
        try:
            os.unlink(EXPECTED_SOCKET)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
