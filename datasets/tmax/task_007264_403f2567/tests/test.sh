#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import signal
import socket
import subprocess
import time
import pytest

USER = pwd.getpwnam("user")


def run_as_user(argv, timeout=4):
    def demote():
        os.setgroups([])
        os.setgid(USER.pw_gid)
        os.setuid(USER.pw_uid)
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, preexec_fn=demote)


def listening_inodes(port, loopback_only=False):
    found = set()
    wanted_port = f"{port:04X}"
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, port_hex = fields[1].split(":")
            if fields[3] != "0A" or port_hex.upper() != wanted_port:
                continue
            if loopback_only and address.upper() != "0100007F":
                continue
            found.add(fields[9])
    return found


def inode_owners(inodes):
    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def listener_pids(port, loopback_only=False, retries=20):
    for _ in range(retries):
        pids = inode_owners(listening_inodes(port, loopback_only))
        if pids:
            return pids
        time.sleep(0.1)
    return set()


def cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return f.read().replace(b"\0", b" ").decode(errors="replace").strip()


def instance_pid():
    result = subprocess.run(
        ["apptainer", "instance", "list", "--json"],
        capture_output=True, text=True, check=True
    )
    data = json.loads(result.stdout)

    def search(value):
        if isinstance(value, dict):
            name = value.get("instance", value.get("name"))
            if name == "backend_svc" and "pid" in value:
                return int(value["pid"])
            for child in value.values():
                answer = search(child)
                if answer is not None:
                    return answer
        elif isinstance(value, list):
            for child in value:
                answer = search(child)
                if answer is not None:
                    return answer
        return None

    pid = search(data)
    assert pid is not None, "Could not obtain the PID of Apptainer instance backend_svc."
    assert os.path.isdir(f"/proc/{pid}"), "The backend_svc instance PID is not running."
    return pid


def receive_banner(port):
    with socket.create_connection(("127.0.0.1", port), timeout=2) as s:
        s.settimeout(2)
        return s.recv(1024).decode("utf-8", errors="ignore")


def test_app_users_txt():
    path = "/home/user/app_users.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "admin:network_engineers", f"Incorrect content in {path}. Expected 'admin:network_engineers', got '{content}'."
    with open(path, "r") as f:
        assert f.read().splitlines() == ["admin:network_engineers"], "app_users.txt must contain exactly one line."


def test_apptainer_instance_running():
    try:
        result = subprocess.run(["apptainer", "instance", "list"], capture_output=True, text=True, check=True)
        assert "backend_svc" in result.stdout, "Apptainer instance 'backend_svc' is not running."
    except FileNotFoundError:
        pytest.fail("apptainer command not found. Is it installed?")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to list apptainer instances: {e.stderr}")


def test_backend_is_inside_instance():
    ipid = instance_pid()
    instance_mnt = os.readlink(f"/proc/{ipid}/ns/mnt")
    pids = listener_pids(9090)
    assert pids, "No process is listening on backend port 9090."

    matching = []
    for pid in pids:
        try:
            args = cmdline(pid)
            mnt = os.readlink(f"/proc/{pid}/ns/mnt")
        except (FileNotFoundError, ProcessLookupError):
            continue
        words = args.split()
        if mnt == instance_mnt and any(os.path.basename(w) == "nc" for w in words) and "9090" in args:
            matching.append(pid)
    assert matching, "Port 9090 is not owned by an nc process running in the backend_svc instance."
    assert "HELLO_FROM_BACKEND" in receive_banner(9090), "The instance backend on port 9090 did not serve the required banner."


def test_port_8080_forwarding():
    pids = listener_pids(8080, loopback_only=True)
    assert pids, "No process is listening on 127.0.0.1:8080."

    valid_socat = []
    for pid in pids:
        try:
            executable = os.path.realpath(f"/proc/{pid}/exe")
            args = cmdline(pid).lower().replace("tcp4", "tcp")
        except (FileNotFoundError, ProcessLookupError):
            continue
        if (executable == "/usr/bin/socat" and
                "tcp-listen:8080" in args and
                "bind=127.0.0.1" in args and
                "fork" in args and
                ("tcp:127.0.0.1:9090" in args or "tcp-connect:127.0.0.1:9090" in args)):
            valid_socat.append(pid)
    assert valid_socat, "Port 8080 is not a forking socat listener forwarding 127.0.0.1:8080 to 127.0.0.1:9090."

    for i in range(2):
        try:
            data = receive_banner(8080)
            assert "HELLO_FROM_BACKEND" in data, f"Connection {i+1}: Did not receive expected banner 'HELLO_FROM_BACKEND' from port 8080. Received: {data}"
        except Exception as e:
            pytest.fail(f"Connection {i+1}: Failed to connect and read from 127.0.0.1:8080: {e}")


def test_healthcheck_executable():
    path = "/home/user/healthcheck"
    assert os.path.exists(path), f"Executable {path} does not exist. Did you compile healthcheck.c?"
    assert os.path.isfile(path), f"{path} is not a regular file."
    assert os.access(path, os.X_OK), f"File {path} exists but is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "healthcheck is not a compiled ELF executable."


def test_repaired_source_and_healthcheck_behavior():
    source = "/home/user/healthcheck.c"
    rebuilt = "/tmp/verifier_healthcheck"
    assert os.path.isfile(source), f"Source file {source} does not exist."
    compile_result = subprocess.run(
        ["gcc", source, "-o", rebuilt], capture_output=True, text=True
    )
    assert compile_result.returncode == 0, f"The repaired healthcheck.c does not compile: {compile_result.stderr}"

    users_path = "/home/user/app_users.txt"
    with open(users_path, "rb") as f:
        original_users = f.read()

    try:
        for program in ("/home/user/healthcheck", rebuilt):
            result = run_as_user([program])
            assert result.returncode == 0, f"{program} failed with the valid access-control file: {result.stdout}{result.stderr}"
            assert "HELLO_FROM_BACKEND" in result.stdout, f"{program} did not print the banner received through the proxy."

        with open(users_path, "w") as f:
            f.write("admin:wrong_group\n")
        os.chown(users_path, USER.pw_uid, USER.pw_gid)
        for program in ("/home/user/healthcheck", rebuilt):
            result = run_as_user([program])
            assert result.returncode != 0, f"{program} accepted an unauthorized group."
            assert "HELLO_FROM_BACKEND" not in result.stdout, f"{program} contacted the backend despite failed authorization."
    finally:
        with open(users_path, "wb") as f:
            f.write(original_users)
        os.chown(users_path, USER.pw_uid, USER.pw_gid)

    proxy_pids = listener_pids(8080, loopback_only=True)
    assert proxy_pids, "The port 8080 proxy disappeared before healthcheck testing."
    try:
        for pid in proxy_pids:
            os.kill(pid, signal.SIGSTOP)
        time.sleep(0.1)
        for program in ("/home/user/healthcheck", rebuilt):
            try:
                result = run_as_user([program], timeout=2)
                assert result.returncode != 0 or "HELLO_FROM_BACKEND" not in result.stdout, \
                    f"{program} produced the backend banner while the port 8080 proxy was stopped."
            except subprocess.TimeoutExpired:
                pass
    finally:
        for pid in proxy_pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass


def test_result_log():
    path = "/home/user/result.log"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "HELLO_FROM_BACKEND" in content, f"Expected 'HELLO_FROM_BACKEND' in {path}, but it was not found."

    result = run_as_user(["/home/user/healthcheck"])
    assert result.returncode == 0, "The submitted healthcheck no longer runs successfully."
    assert content.strip() == result.stdout.strip(), "result.log does not match the output of the submitted healthcheck executable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
