#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import os
import re
import signal
import socket
import subprocess
import time

import pytest

HOME = "/home/user"
EXPECTED_RESPONSE = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
PORTS = (8080, 9001, 9002)


def kill_port_owners(ports):
    wanted_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].split(":")[1], 16)
                    state = fields[3]
                    if local_port in ports and state == "0A":
                        wanted_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in wanted_inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.5)


def raw_request(port, path="/"):
    with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
        sock.settimeout(2)
        sock.sendall(
            f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".encode()
        )
        chunks = []
        while True:
            try:
                data = sock.recv(65536)
            except socket.timeout:
                pytest.fail(f"Server on port {port} did not close its response")
            if not data:
                break
            chunks.append(data)
        return b"".join(chunks)


def assert_http_ok(port):
    response = raw_request(port, "/verifier-check")
    head, separator, body = response.partition(b"\r\n\r\n")
    assert separator, f"Malformed HTTP response from port {port}: {response!r}"
    assert head.startswith(b"HTTP/1.1 200 ") or head.startswith(b"HTTP/1.0 200 "), response
    assert body == b"OK", f"Response body from port {port} was {body!r}, expected b'OK'"


def backend_pids(port):
    found = []
    expected_exe = os.path.realpath(f"{HOME}/backend")
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            exe = os.path.realpath(os.readlink(f"/proc/{entry}/exe"))
            cmdline = open(f"/proc/{entry}/cmdline", "rb").read().split(b"\0")
            uid = os.stat(f"/proc/{entry}").st_uid
        except (FileNotFoundError, PermissionError, OSError):
            continue
        args = [arg.decode(errors="replace") for arg in cmdline if arg]
        if exe == expected_exe and str(port) in args and uid == 1000:
            found.append(int(entry))
    return found


def wait_for_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Port {port} did not become available")


@pytest.fixture(scope="session", autouse=True)
def deploy_fresh():
    deploy_script = f"{HOME}/deploy.sh"
    assert os.path.isfile(deploy_script), f"Deployment script {deploy_script} does not exist."
    assert os.access(deploy_script, os.X_OK), f"Deployment script {deploy_script} is not executable."

    kill_port_owners(set(PORTS))
    for name in ("nginx", "backend"):
        subprocess.run(["pkill", "-9", "-u", "user", "-x", name], check=False)
    time.sleep(0.5)

    try:
        os.remove(f"{HOME}/backend")
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", f"HOME={HOME}", "bash", f"{HOME}/deploy.sh"],
        cwd=HOME,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"deploy.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    for port in PORTS:
        wait_for_port(port)
    yield


def test_deploy_script_exists_and_executable():
    deploy_script = "/home/user/deploy.sh"
    assert os.path.isfile(deploy_script), f"Deployment script {deploy_script} does not exist."
    assert os.access(deploy_script, os.X_OK), f"Deployment script {deploy_script} is not executable."


def test_nginx_temp_dir_exists():
    temp_dir = "/home/user/nginx_temp"
    assert os.path.isdir(temp_dir), f"Nginx temp directory {temp_dir} was not created."


def test_backend_source_builds_and_is_fast_and_exact():
    source = f"{HOME}/backend.c"
    assert os.path.isfile(source), "backend.c is missing"
    text = open(source).read()
    assert not re.search(r"\bsleep\s*\(", text), "backend.c still contains an artificial sleep"

    test_binary = "/tmp/backend_from_submitted_source"
    build = subprocess.run(
        ["gcc", "-O2", "-pthread", source, "-o", test_binary],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"backend.c does not compile:\n{build.stderr}"

    test_port = 19091
    kill_port_owners({test_port})
    proc = subprocess.Popen(
        ["runuser", "-u", "user", "--", test_binary, str(test_port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_port(test_port)
        assert raw_request(test_port) == EXPECTED_RESPONSE
        start = time.monotonic()
        with concurrent.futures.ThreadPoolExecutor(max_workers=40) as pool:
            responses = list(pool.map(lambda _: raw_request(test_port), range(100)))
        elapsed = time.monotonic() - start
        assert all(response == EXPECTED_RESPONSE for response in responses)
        assert elapsed < 3.0, f"Submitted backend source handles requests sequentially or too slowly ({elapsed:.2f}s)"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
        kill_port_owners({test_port})


def test_deployed_backend_binary_and_two_instances():
    backend = f"{HOME}/backend"
    assert os.path.isfile(backend), "deploy.sh did not create /home/user/backend"
    assert os.access(backend, os.X_OK), "Compiled backend is not executable"
    with open(backend, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The deployed backend is not a compiled ELF executable"

    pids_9001 = backend_pids(9001)
    pids_9002 = backend_pids(9002)
    assert len(pids_9001) == 1, f"Expected one submitted backend instance on port 9001, found {pids_9001}"
    assert len(pids_9002) == 1, f"Expected one submitted backend instance on port 9002, found {pids_9002}"
    assert len(set(pids_9001 + pids_9002)) == 2, "Two distinct backend instances were not started"

    assert raw_request(9001) == EXPECTED_RESPONSE
    assert raw_request(9002) == EXPECTED_RESPONSE

    ss = subprocess.run(["ss", "-lnt"], capture_output=True, text=True, check=True).stdout
    for port in (9001, 9002):
        lines = [line for line in ss.splitlines() if re.search(rf":{port}\s", line)]
        assert lines, f"No listening socket found on backend port {port}"
        fields = lines[0].split()
        assert int(fields[2]) >= 1024, f"Backend listen backlog on port {port} is below 1024: {lines[0]}"


def test_nginx_configuration_and_process():
    config_path = f"{HOME}/nginx.conf"
    assert os.path.isfile(config_path), "nginx.conf is missing"
    config = re.sub(r"#.*", "", open(config_path).read())

    assert re.search(r"\blisten\s+[^;]*\b8080\b[^;]*;", config), "Nginx does not listen on port 8080"
    assert re.search(r"\bserver\s+127\.0\.0\.1:9001\s*;", config), "Nginx upstream 9001 is missing"
    assert re.search(r"\bserver\s+127\.0\.0\.1:9002\s*;", config), "Nginx upstream 9002 is missing"
    assert re.search(r"\bproxy_pass\s+http://[A-Za-z0-9_-]+\s*;", config), "Nginx is not configured to proxy to an upstream"
    assert re.search(r"\bpid\s+/home/user/nginx_temp/[^;]+;", config), "Nginx pid is not stored in nginx_temp"
    assert re.search(r"\bclient_body_temp_path\s+/home/user/nginx_temp(?:/[^;\s]+)?", config), "client_body_temp_path is not under nginx_temp"
    assert "/var/run" not in config and "/var/log/nginx" not in config, "Nginx still uses privileged system paths"
    assert not re.search(r"\breturn\s+2\d\d\b", config), "Nginx serves a fabricated direct response instead of proxying"

    master_processes = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            cmd = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
            uid = os.stat(f"/proc/{entry}").st_uid
        except (FileNotFoundError, PermissionError):
            continue
        if "nginx: master process" in cmd and "-c /home/user/nginx.conf" in cmd:
            master_processes.append((int(entry), uid))
    assert master_processes, "Nginx was not started with /home/user/nginx.conf"
    assert all(uid == 1000 for _, uid in master_processes), "Nginx master is not running as the local user"
    assert_http_ok(8080)


def test_system_performance_and_correctness():
    time.sleep(2)

    try:
        result = subprocess.run(
            ["wrk", "-t4", "-c100", "-d10s", "http://127.0.0.1:8080/"],
            capture_output=True, text=True, timeout=20
        )
    except FileNotFoundError:
        pytest.fail("wrk command not found. Ensure wrk is installed in the environment.")
    except subprocess.TimeoutExpired:
        pytest.fail("wrk load test timed out.")

    output = result.stdout
    assert result.returncode == 0, f"wrk failed:\n{result.stdout}\n{result.stderr}"

    errors = re.search(r"Non-2xx or 3xx responses:\s+(\d+)", output)
    if errors and int(errors.group(1)) > 0:
        pytest.fail(f"Found {errors.group(1)} Bad Gateway or other non-2xx/3xx errors.")

    socket_errors = re.search(r"Socket errors:\s+(.*)", output)
    if socket_errors:
        pytest.fail(f"Socket errors detected: {socket_errors.group(1)}")

    rps_match = re.search(r"Requests/sec:\s+([\d\.]+)", output)
    assert rps_match is not None, f"Could not parse Requests/sec from wrk output:\n{output}"

    rps = float(rps_match.group(1))
    threshold = 2000.0
    assert rps >= threshold, f"Throughput too low: achieved {rps} RPS, expected >= {threshold} RPS."
    assert_http_ok(8080)


def test_nginx_actually_depends_on_both_upstreams():
    pids1 = backend_pids(9001)
    pids2 = backend_pids(9002)
    assert len(pids1) == 1 and len(pids2) == 1

    os.kill(pids1[0], signal.SIGKILL)
    time.sleep(0.3)
    for _ in range(8):
        assert_http_ok(8080)

    restarted = subprocess.Popen(
        ["runuser", "-u", "user", "--", f"{HOME}/backend", "9001"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_port(9001)
        reload_result = subprocess.run(
            ["runuser", "-u", "user", "--", "nginx", "-s", "reload", "-c", f"{HOME}/nginx.conf"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert reload_result.returncode == 0, reload_result.stderr
        time.sleep(0.5)

        os.kill(pids2[0], signal.SIGKILL)
        time.sleep(0.3)
        for _ in range(8):
            assert_http_ok(8080)

        for pid in backend_pids(9001):
            os.kill(pid, signal.SIGKILL)
        time.sleep(0.5)
        try:
            response = raw_request(8080)
            _, _, body = response.partition(b"\r\n\r\n")
            assert body != b"OK", "Nginx still returns OK with both required backends stopped"
        except (ConnectionRefusedError, ConnectionResetError, socket.timeout, OSError):
            pass
    finally:
        restarted.terminate()
        try:
            restarted.wait(timeout=2)
        except subprocess.TimeoutExpired:
            restarted.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
