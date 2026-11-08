#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import signal
import socket
import stat
import subprocess
import time
import urllib.error
import urllib.request

import pytest

EXPECTED_RAW = (b"HTTP/1.1 200 OK\r\n"
                b"Content-Length: 18\r\n"
                b"Connection: close\r\n\r\n"
                b"SUCCESS_DEPLOYMENT")
STATE = {}


def kill_listeners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[-1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
        except OSError:
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def receive_all(sock):
    chunks = []
    while True:
        data = sock.recv(4096)
        if not data:
            return b"".join(chunks)
        chunks.append(data)


def wait_for_unix_socket(path, proc=None, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            raise AssertionError(f"backend exited early with status {proc.returncode}")
        if os.path.exists(path) and stat.S_ISSOCK(os.stat(path).st_mode):
            return
        time.sleep(0.05)
    raise AssertionError(f"UNIX socket was not created: {path}")


def exercise_backend(executable, socket_path):
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass
    # A pre-existing filesystem entry verifies that the backend unlinks the path.
    with open(socket_path, "wb") as f:
        f.write(b"stale")

    proc = subprocess.Popen([executable, socket_path], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        wait_for_unix_socket(socket_path, proc)
        for request in (
            b"GET /alpha HTTP/1.1\r\nHost: test\r\n\r\n",
            b"POST /different HTTP/1.0\r\nContent-Length: 3\r\n\r\nxyz",
        ):
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(3)
                client.connect(socket_path)
                client.sendall(request)
                assert receive_all(client) == EXPECTED_RAW
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=2)
        try:
            os.unlink(socket_path)
        except FileNotFoundError:
            pass


def backend_pids_for(executable):
    wanted = os.path.realpath(executable)
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if os.path.realpath(os.readlink(f"/proc/{entry}/exe")) != wanted:
                continue
            cmdline = open(f"/proc/{entry}/cmdline", "rb").read().split(b"\0")
            if b"/home/user/app/current/backend.sock" in cmdline:
                result.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def wait_for_backend_process(executable, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = backend_pids_for(executable)
        if pids:
            return pids
        time.sleep(0.05)
    raise AssertionError("no running process is executing the current backend_service")


def run_deploy():
    started = int(time.time())
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/home/user/deploy.sh"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE, text=True, timeout=20)
    finished = int(time.time())
    assert result.returncode == 0, f"deploy.sh failed: {result.stderr}"

    current = "/home/user/app/current"
    assert os.path.islink(current)
    release = os.path.realpath(current)
    releases_root = os.path.realpath("/home/user/app/releases")
    assert os.path.dirname(release) == releases_root, \
        f"current points outside releases/: {release}"
    name = os.path.basename(release)
    assert name.isdigit(), f"release name is not a UNIX timestamp: {name}"
    timestamp = int(name)
    assert started <= timestamp <= finished, \
        f"release timestamp {timestamp} was not generated by this deployment"
    assert os.path.isdir(release)
    return release


@pytest.fixture(scope="session", autouse=True)
def deployed_environment():
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "backend_service"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    kill_listeners(8080)
    subprocess.run(["rm", "-rf", "/home/user/app"], check=True)

    source = "/home/user/src/backend.c"
    assert os.path.isfile(source), f"backend source not found at {source}"
    compiled = "/tmp/verifier_backend"
    build = subprocess.run(["gcc", source, "-o", compiled], stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True)
    assert build.returncode == 0, f"backend.c does not compile: {build.stderr}"
    exercise_backend(compiled, "/tmp/verifier_backend.sock")

    first_release = run_deploy()
    first_binary = os.path.join(first_release, "backend_service")
    first_pids = wait_for_backend_process(first_binary)

    # Ensure a second invocation receives a distinct current UNIX timestamp.
    target_second = int(time.time()) + 1
    while int(time.time()) < target_second:
        time.sleep(0.05)
    second_release = run_deploy()
    assert second_release != first_release, "a second deployment did not create a new release"
    assert os.path.isdir(first_release), "the previous staged release was not retained"

    deadline = time.time() + 5
    while time.time() < deadline and any(os.path.exists(f"/proc/{p}") for p in first_pids):
        time.sleep(0.05)
    assert not any(os.path.exists(f"/proc/{p}") for p in first_pids), \
        "the prior backend process was not stopped during redeployment"

    current_binary = "/home/user/app/current/backend_service"
    with open(current_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "backend_service is not a compiled ELF executable"
    current_pids = wait_for_backend_process(current_binary)
    user_uid = pwd.getpwnam("user").pw_uid
    for pid in current_pids:
        with open(f"/proc/{pid}/status") as f:
            uid_line = next(line for line in f if line.startswith("Uid:"))
        assert int(uid_line.split()[1]) == user_uid, "backend is not running rootlessly as user"

    # Exercise the deployed executable itself through its deployed UNIX socket.
    unix_path = "/home/user/app/current/backend.sock"
    wait_for_unix_socket(unix_path)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(3)
        client.connect(unix_path)
        client.sendall(b"GET /deployed-check HTTP/1.1\r\nHost: local\r\n\r\n")
        assert receive_all(client) == EXPECTED_RAW

    os.makedirs("/home/user/client_body", exist_ok=True)
    for stale in ("/home/user/nginx.pid",):
        try:
            os.unlink(stale)
        except FileNotFoundError:
            pass
    nginx = subprocess.Popen(
        ["runuser", "-u", "user", "--", "nginx", "-c", "/home/user/nginx.conf"],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, start_new_session=True)
    STATE["nginx"] = nginx
    STATE["backend_pids"] = current_pids

    deadline = time.time() + 5
    last_error = None
    while time.time() < deadline:
        if nginx.poll() is not None:
            raise AssertionError(f"nginx exited early: {nginx.stderr.read().decode(errors='replace')}")
        try:
            with urllib.request.urlopen("http://localhost:8080/", timeout=1) as response:
                if response.status == 200 and response.read() == b"SUCCESS_DEPLOYMENT":
                    break
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    else:
        raise AssertionError(f"nginx did not become ready: {last_error}")

    yield

    for pid in STATE.get("backend_pids", []):
        try:
            os.kill(pid, signal.SIGCONT)
        except ProcessLookupError:
            pass
    try:
        os.killpg(nginx.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass


def test_deploy_script_exists_and_executable():
    deploy_script_path = "/home/user/deploy.sh"
    assert os.path.exists(deploy_script_path), f"Deploy script not found at {deploy_script_path}"
    assert os.path.isfile(deploy_script_path), f"{deploy_script_path} is not a file"
    st = os.stat(deploy_script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Deploy script {deploy_script_path} is not executable"


def test_app_current_is_symlink():
    current_path = "/home/user/app/current"
    assert os.path.exists(current_path), f"Symlink target {current_path} does not exist"
    assert os.path.islink(current_path), f"{current_path} is not a symbolic link"


def test_backend_service_exists():
    backend_service_path = "/home/user/app/current/backend_service"
    assert os.path.exists(backend_service_path), f"Backend service executable not found at {backend_service_path}"
    assert os.path.isfile(backend_service_path), f"{backend_service_path} is not a file"
    st = os.stat(backend_service_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Backend service {backend_service_path} is not executable"


def test_nginx_is_dependent_on_compiled_backend():
    pids = backend_pids_for("/home/user/app/current/backend_service")
    assert pids, "compiled current backend is not running"
    for pid in pids:
        os.kill(pid, signal.SIGSTOP)
    client = socket.create_connection(("127.0.0.1", 8080), timeout=2)
    try:
        client.settimeout(0.7)
        client.sendall(b"GET /dependency-check HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        with pytest.raises(socket.timeout):
            client.recv(1)
        for pid in pids:
            os.kill(pid, signal.SIGCONT)
        client.settimeout(3)
        response = receive_all(client)
        assert response.endswith(b"\r\n\r\nSUCCESS_DEPLOYMENT")
    finally:
        for pid in pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        client.close()


def test_nginx_and_backend_integration():
    url = "http://localhost:8080/"
    max_retries = 3
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as response:
                status = response.getcode()
                body = response.read().decode('utf-8').strip()
                assert status == 200, f"Expected HTTP 200, got {status}"
                assert body == "SUCCESS_DEPLOYMENT", f"Expected response body 'SUCCESS_DEPLOYMENT', got '{body}'"
                return
        except urllib.error.URLError as e:
            if attempt == max_retries - 1:
                assert False, f"Failed to connect to Nginx on port 8080: {e}"
            time.sleep(1)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
