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
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import signal
import stat
import subprocess
import time
import secrets

import pytest
import requests

APP_DIR = "/app/provisioner-1.0"
BINARY = os.path.join(APP_DIR, "provisioner")
SCRIPT = "/home/user/setup_and_run.sh"
PORT_HEX = format(8080, "04X")


def listening_socket_inodes():
    found = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                rows = f.readlines()[1:]
        except FileNotFoundError:
            continue
        for row in rows:
            fields = row.split()
            local_address = fields[1]
            state = fields[3]
            if state != "0A":
                continue
            address, port = local_address.rsplit(":", 1)
            if port.upper() == PORT_HEX:
                found.append((address.upper(), fields[9]))
    return found


def pids_for_inodes(inodes):
    wanted = set(inodes)
    result = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            fds = os.listdir(fd_dir)
        except (FileNotFoundError, PermissionError):
            continue
        for fd in fds:
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except (FileNotFoundError, PermissionError, OSError):
                continue
            if target.startswith("socket:[") and target[8:-1] in wanted:
                result.add(int(entry))
                break
    return result


def stop_port_8080():
    deadline = time.time() + 5
    while time.time() < deadline:
        sockets = listening_socket_inodes()
        if not sockets:
            return
        pids = pids_for_inodes(inode for _, inode in sockets)
        for pid in pids:
            if pid != os.getpid():
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        time.sleep(0.15)
    sockets = listening_socket_inodes()
    pids = pids_for_inodes(inode for _, inode in sockets)
    for pid in pids:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while time.time() < deadline and listening_socket_inodes():
        time.sleep(0.1)
    assert not listening_socket_inodes(), "Could not stop the previous listener on port 8080"


def wait_for_listener(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listening_socket_inodes():
            try:
                requests.get("http://127.0.0.1:8080/", timeout=0.3)
            except requests.exceptions.RequestException:
                pass
            return
        time.sleep(0.1)
    pytest.fail("No service began listening on port 8080")


def run_setup():
    env = os.environ.copy()
    env.pop("BASE_DIR", None)
    env.pop("WWW_DIR", None)
    subprocess.run(
        [SCRIPT], check=True, timeout=20, env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    wait_for_listener()


def assert_loopback_binary_listener():
    sockets = listening_socket_inodes()
    assert sockets, "No listening socket was found on port 8080"
    # 127.0.0.1 is represented in little-endian form in /proc/net/tcp.
    assert all(address == "0100007F" for address, _ in sockets), (
        f"Port 8080 must bind specifically to 127.0.0.1; found addresses {sockets}"
    )
    pids = pids_for_inodes(inode for _, inode in sockets)
    assert pids, "Could not identify the process listening on port 8080"
    expected = os.path.realpath(BINARY)
    executables = []
    for pid in pids:
        try:
            executables.append(os.path.realpath(f"/proc/{pid}/exe"))
        except OSError:
            pass
    assert expected in executables, (
        f"The listener is not the compiled {BINARY}; listener executables: {executables}"
    )


def test_setup_script_exists_and_executable():
    script_path = "/home/user/setup_and_run.sh"
    assert os.path.isfile(script_path), f"Setup script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Setup script {script_path} is not executable."


def test_package_build_setup_and_idempotence():
    stop_port_8080()

    # Verify that the vendored package itself builds successfully with make.
    if os.path.lexists(BINARY):
        os.unlink(BINARY)
    subprocess.run(
        ["make", "-C", APP_DIR], check=True, timeout=20,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    assert os.path.isfile(BINARY), "make did not create the provisioner binary"
    assert os.access(BINARY, os.X_OK), "The provisioner produced by make is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The provisioner produced by make is not an ELF binary"

    # Remove it again so setup_and_run.sh must perform its required compilation.
    os.unlink(BINARY)
    shutil.rmtree("/home/user/managed_users/testuser1", ignore_errors=True)
    shutil.rmtree("/home/user/public_web/testuser1", ignore_errors=True)

    run_setup()
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "setup_and_run.sh did not compile the missing provisioner binary"
    )
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF"
    assert os.path.isdir("/home/user/managed_users")
    assert os.path.isdir("/home/user/public_web")
    assert_loopback_binary_listener()

    # A second invocation must succeed and leave a working service.
    run_setup()
    assert_loopback_binary_listener()


def test_missing_environment_does_not_crash_binary_and_service_is_restored():
    stop_port_8080()
    env = os.environ.copy()
    env.pop("BASE_DIR", None)
    env.pop("WWW_DIR", None)
    proc = subprocess.Popen(
        [BINARY], cwd=APP_DIR, env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + 2
        while time.time() < deadline and proc.poll() is None and not listening_socket_inodes():
            time.sleep(0.05)
        if listening_socket_inodes() and proc.poll() is None:
            try:
                requests.get(
                    "http://127.0.0.1:8080/provision",
                    params={"username": "missing_env_probe", "ip": "10.1.2.3"},
                    timeout=2,
                )
            except requests.exceptions.RequestException:
                pass
            time.sleep(0.2)
        rc = proc.poll()
        assert rc != -signal.SIGSEGV, "provisioner crashed when required environment variables were absent"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        stop_port_8080()
    run_setup()
    assert_loopback_binary_listener()


def test_provisioner_service_and_side_effects():
    # Make the request to the provisioner service
    url = "http://127.0.0.1:8080/provision"
    params = {
        "username": "testuser1",
        "ip": "192.168.5.5"
    }

    try:
        response = requests.get(url, params=params, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the provisioner service on 127.0.0.1:8080: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    assert response.text.strip() == "OK", f"Expected response body 'OK', got '{response.text}'"

    # Verify side effects
    base_dir = "/home/user/managed_users/testuser1"
    www_dir = "/home/user/public_web/testuser1"
    symlink_path = os.path.join(base_dir, "www")
    route_file = os.path.join(base_dir, "route.sh")

    assert os.path.isdir(base_dir), f"Directory {base_dir} was not created."
    assert os.path.isdir(www_dir), f"Directory {www_dir} was not created."

    assert os.path.islink(symlink_path), f"Symlink {symlink_path} was not created."
    target = os.readlink(symlink_path)
    assert target == www_dir, f"Symlink {symlink_path} points to {target}, expected {www_dir}."

    assert os.path.isfile(route_file), f"File {route_file} was not created."
    with open(route_file, "r") as f:
        content = f.read().strip()

    expected_content = "ip route add 192.168.5.5 via 10.0.0.1"
    assert content == expected_content, f"File {route_file} content mismatch. Expected '{expected_content}', got '{content}'."


def test_random_provisioning_requests_are_honored_exactly():
    url = "http://127.0.0.1:8080/provision"
    cases = []
    for index in range(2):
        username = f"audit_{secrets.token_hex(6)}_{index}"
        ip = f"10.{secrets.randbelow(200) + 1}.{secrets.randbelow(256)}.{secrets.randbelow(254) + 1}"
        cases.append((username, ip))

    for username, ip in cases:
        base_dir = os.path.join("/home/user/managed_users", username)
        www_dir = os.path.join("/home/user/public_web", username)
        assert not os.path.lexists(base_dir)
        assert not os.path.lexists(www_dir)

        response = requests.get(
            url, params={"username": username, "ip": ip}, timeout=5
        )
        assert response.status_code == 200
        assert response.content == b"OK"
        assert os.path.isdir(base_dir)
        assert os.path.isdir(www_dir)

        symlink_path = os.path.join(base_dir, "www")
        assert os.path.islink(symlink_path)
        assert os.readlink(symlink_path) == www_dir

        route_file = os.path.join(base_dir, "route.sh")
        assert os.path.isfile(route_file)
        with open(route_file, "rb") as f:
            actual = f.read()
        expected = f"ip route add {ip} via 10.0.0.1".encode()
        assert actual == expected

    # Rerunning setup after state has been created must also be harmless.
    before = {}
    for username, _ in cases:
        route_file = os.path.join("/home/user/managed_users", username, "route.sh")
        with open(route_file, "rb") as f:
            before[route_file] = f.read()
    run_setup()
    assert_loopback_binary_listener()
    for route_file, expected in before.items():
        with open(route_file, "rb") as f:
            assert f.read() == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
