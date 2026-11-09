#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest

USER_UID = pwd.getpwnam("user").pw_uid
WORKER = "/home/user/bin/worker"


def send_tcp_message(port, message, chunks=None):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=2) as s:
            s.settimeout(2)
            if chunks is None:
                s.sendall(message.encode("utf-8"))
            else:
                for chunk in chunks:
                    s.sendall(chunk.encode("utf-8"))
                    time.sleep(0.04)
            data = b""
            while True:
                try:
                    part = s.recv(1024)
                except socket.timeout:
                    break
                if not part:
                    break
                data += part
            return data.decode("utf-8").strip()
    except Exception:
        return None


def check_process_running(cmd_substring):
    try:
        output = subprocess.check_output(["pgrep", "-f", cmd_substring], text=True)
        return len(output.strip().split("\n")) > 0
    except subprocess.CalledProcessError:
        return False


def processes():
    result = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            pid = int(entry.name)
            st = entry.stat()
            raw = (entry / "cmdline").read_bytes()
            argv = [x.decode(errors="replace") for x in raw.split(b"\0") if x]
            exe = os.path.realpath(entry / "exe")
            result.append((pid, st.st_uid, exe, argv))
        except (FileNotFoundError, ProcessLookupError, PermissionError, OSError):
            pass
    return result


def strict_worker_pids(port, instance):
    wanted = [WORKER, str(port), instance]
    return [pid for pid, uid, exe, argv in processes()
            if uid == USER_UID and exe == WORKER and argv == wanted]


def monitor_pids():
    found = []
    for pid, uid, exe, argv in processes():
        if uid != USER_UID or not argv:
            continue
        if "/home/user/monitor.py" in argv and os.path.basename(exe).startswith("python"):
            found.append(pid)
    return found


def wait_until(predicate, timeout=8, interval=0.15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return predicate()


def nginx_owns_8080():
    inodes = set()
    try:
        with open("/proc/net/tcp") as f:
            next(f)
            for line in f:
                fields = line.split()
                local, state, inode = fields[1], fields[3], fields[9]
                if local.upper() == "0100007F:1F90" and state == "0A":
                    inodes.add(inode)
    except OSError:
        return False
    if not inodes:
        return False
    nginx_pids = {pid for pid, uid, exe, argv in processes()
                  if uid == USER_UID and os.path.basename(exe) == "nginx"}
    for pid in nginx_pids:
        try:
            for fd in (Path("/proc") / str(pid) / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return True
        except OSError:
            pass
    return False


@pytest.fixture(scope="session", autouse=True)
def deploy_from_package():
    required = [
        "/home/user/src/worker.cpp",
        "/home/user/nginx/nginx.conf",
        "/home/user/monitor.py",
        "/home/user/deploy.sh",
    ]
    for path in required:
        assert os.path.isfile(path), f"Expected file {path} does not exist."

    # Force deploy.sh to create the binary rather than accepting a pre-existing
    # executable, then run it twice to exercise its required idempotence.
    poison = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "-c",
         "rm -f /home/user/bin/worker; mkdir -p /home/user/bin; "
         "printf 'not an executable\\n' > /home/user/bin/worker; chmod +x /home/user/bin/worker"],
        timeout=10,
    )
    assert poison.returncode == 0

    for _ in range(2):
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "bash", "/home/user/deploy.sh"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
        assert result.returncode == 0, "deploy.sh did not exit successfully"
        time.sleep(1)

    assert Path(WORKER).read_bytes()[:4] == b"\x7fELF", "deploy.sh did not compile an ELF worker"
    yield


def test_files_exist():
    expected_files = [
        "/home/user/src/worker.cpp",
        "/home/user/bin/worker",
        "/home/user/nginx/nginx.conf",
        "/home/user/monitor.py",
        "/home/user/deploy.sh"
    ]
    for f in expected_files:
        assert os.path.isfile(f), f"Expected file {f} does not exist."


def test_worker_source_compiles_and_handles_unpredictable_instance():
    subprocess.run(
        ["g++", "-std=c++17", "-O2", "/home/user/src/worker.cpp", "-o", "/tmp/audited_worker"],
        check=True,
        timeout=30,
    )
    assert Path("/tmp/audited_worker").read_bytes()[:4] == b"\x7fELF"

    no_args = subprocess.run(["/tmp/audited_worker"], timeout=2)
    extra_args = subprocess.run(["/tmp/audited_worker", "12345", "x", "extra"], timeout=2)
    assert no_args.returncode != 0, "worker accepted missing arguments"
    assert extra_args.returncode != 0, "worker accepted more than two arguments"

    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    instance = "audit_" + os.urandom(8).hex()
    proc = subprocess.Popen(["/tmp/audited_worker", str(port), instance],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_until(lambda: send_tcp_message(port, "PING\n") == "PONG", timeout=4)
        assert send_tcp_message(port, "", chunks=["VER", "SION", "\n"]) == "v2_" + instance
        assert send_tcp_message(port, "VERSION\njunk") == "v2_" + instance
        assert send_tcp_message(port, "UNKNOWN_" + os.urandom(5).hex() + "\n") == ""
    finally:
        proc.kill()
        proc.wait(timeout=3)


def test_processes_running():
    assert check_process_running("nginx"), "Nginx process is not running."
    assert check_process_running("monitor.py"), "Monitor process is not running."
    for port in ["9001", "9002", "9003"]:
        assert check_process_running(f"worker {port}"), f"Worker process for port {port} is not running."

    for port, instance in [(9001, "inst_1"), (9002, "inst_2"), (9003, "inst_3")]:
        assert strict_worker_pids(port, instance), f"Port {port} is not served by the compiled worker with correct arguments"
    assert monitor_pids(), "monitor.py is not running under Python as user"


def test_nginx_configuration_and_real_listener():
    text = Path("/home/user/nginx/nginx.conf").read_text()
    uncommented = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
    assert "stream" in uncommented, "nginx.conf has no stream context"
    for endpoint in ["127.0.0.1:9001", "127.0.0.1:9002", "127.0.0.1:9003"]:
        assert endpoint in uncommented, f"nginx.conf lacks backend {endpoint}"
    assert "127.0.0.1:8080" in uncommented, "nginx.conf does not listen on 127.0.0.1:8080"
    assert "proxy_pass" in uncommented, "nginx.conf does not proxy stream traffic"
    assert "/home/user/nginx/" in uncommented, "nginx.conf does not use user-space runtime paths"

    nginx = [(pid, argv) for pid, uid, exe, argv in processes()
             if uid == USER_UID and os.path.basename(exe) == "nginx"]
    assert nginx, "No genuine nginx executable is running as user"
    assert any("nginx.conf" in " ".join(argv) for _, argv in nginx), "Running nginx was not started with the custom configuration"
    assert nginx_owns_8080(), "The genuine nginx process does not own the 127.0.0.1:8080 listener"


def test_nginx_proxy_round_robin():
    responses = set()
    for _ in range(5):
        resp = send_tcp_message(8080, "VERSION\n")
        assert resp is not None, "Failed to connect to Nginx proxy on port 8080 or no response."
        assert resp.startswith("v2_"), f"Unexpected response from worker: {resp}"
        responses.add(resp)
    assert len(responses) >= 2, "Nginx does not appear to be load balancing across multiple instances."

    observed = [send_tcp_message(8080, "VERSION\n") for _ in range(12)]
    assert set(observed) == {"v2_inst_1", "v2_inst_2", "v2_inst_3"}, \
        f"Proxy did not round-robin over all three specified workers: {observed}"
    random_bad = "BAD_" + os.urandom(8).hex() + "\n"
    assert send_tcp_message(8080, random_bad) == ""
    assert send_tcp_message(8080, "PING\n") == "PONG"


def test_monitor_revives_worker():
    # Preserve the original restart assertion.
    subprocess.run(["pkill", "-f", "worker 9002"])
    assert not check_process_running("worker 9002"), "Failed to kill worker 9002 for testing."
    time.sleep(5)
    assert check_process_running("worker 9002"), "Monitor failed to revive worker 9002."
    resp = send_tcp_message(9002, "PING\n")
    assert resp == "PONG", f"Revived worker 9002 did not respond with PONG, got: {resp}"
    assert strict_worker_pids(9002, "inst_2"), "Monitor revived port 9002 with the wrong executable or instance ID"

    # Establish that the submitted monitor.py, rather than an unrelated process,
    # is responsible for restarting workers.
    for pid in monitor_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    assert wait_until(lambda: not monitor_pids(), timeout=3)
    for pid in strict_worker_pids(9002, "inst_2"):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    assert wait_until(lambda: not strict_worker_pids(9002, "inst_2"), timeout=2)
    time.sleep(3)
    assert not strict_worker_pids(9002, "inst_2"), "A process other than monitor.py is supervising workers"

    subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "-c",
         "nohup python3 /home/user/monitor.py >/home/user/nginx/logs/monitor.log 2>&1 &"],
        check=True,
        timeout=5,
    )
    assert wait_until(lambda: monitor_pids(), timeout=3), "Submitted monitor.py did not stay running"
    assert wait_until(lambda: strict_worker_pids(9002, "inst_2"), timeout=7), \
        "Submitted monitor.py did not respawn the correct worker"
    assert send_tcp_message(9002, "PING\n") == "PONG"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
