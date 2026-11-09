#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import stat
import subprocess
import tempfile
import time
import urllib.request

ROOT = "/home/user/restore"
SOURCE = ROOT + "/src/backend.c"
BINARY = ROOT + "/bin/backend"
SOCKET = ROOT + "/run/backend.sock"
PIDFILE = ROOT + "/run/backend.pid"
SUCCESS = ROOT + "/success.txt"
URL = "http://127.0.0.1:8080/api"
EXPECTED = "ANALYTICS_RESTORE"


def read_pid():
    assert os.path.isfile(PIDFILE), f"PID file {PIDFILE} is missing."
    value = open(PIDFILE).read().strip()
    assert value.isdigit(), f"PID file {PIDFILE} does not contain a valid integer PID."
    return int(value)


def process_running(pid):
    proc = f"/proc/{pid}"
    if not os.path.isdir(proc):
        return False
    try:
        fields = open(f"{proc}/stat").read().split()
        return len(fields) > 2 and fields[2] != "Z"
    except OSError:
        return False


def cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return f.read().replace(b"\0", b" ").decode(errors="replace")


def assert_process_executable(pid, expected_exe):
    assert process_running(pid), f"Process with PID {pid} is not running."
    assert "backend" in cmdline(pid), f"Process {pid} does not appear to be a backend process."
    actual = os.path.realpath(f"/proc/{pid}/exe")
    assert os.path.samefile(actual, expected_exe), (
        f"PID {pid} is executing {actual}, not the required compiled executable {expected_exe}."
    )


def assert_socket_owned_by(pid):
    assert os.path.exists(SOCKET), f"Socket file {SOCKET} is missing."
    assert stat.S_ISSOCK(os.stat(SOCKET).st_mode), f"{SOCKET} is not a Unix socket."
    inode = os.stat(SOCKET).st_ino
    targets = []
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            targets.append(os.readlink(f"/proc/{pid}/fd/{fd}"))
        except OSError:
            pass
    assert f"socket:[{inode}]" in targets, (
        f"The backend PID {pid} does not own the Unix socket at {SOCKET}."
    )


def direct_backend_request():
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(2)
    try:
        client.connect(SOCKET)
        client.sendall(b"GET /verifier-direct HTTP/1.1\r\nHost: verifier\r\nConnection: close\r\n\r\n")
        data = b""
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            data += chunk
    finally:
        client.close()
    assert b"\r\n\r\n" in data, "Backend did not return a valid HTTP response."
    body = data.split(b"\r\n\r\n", 1)[1].decode().strip()
    assert body == EXPECTED, f"Direct backend response was {body!r}."


def nginx_request(timeout=2):
    req = urllib.request.Request(URL, headers={"Connection": "close"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read().decode().strip()


def wait_for_backend(expected_exe, timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            pid = read_pid()
            assert_process_executable(pid, expected_exe)
            assert_socket_owned_by(pid)
            return pid
        except Exception as exc:
            last_error = exc
            time.sleep(0.05)
    raise AssertionError(f"Backend did not become ready: {last_error}")


def stop_process(pid):
    if not process_running(pid):
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 3
    while time.time() < deadline and process_running(pid):
        time.sleep(0.05)
    if process_running(pid):
        os.kill(pid, signal.SIGKILL)
        time.sleep(0.1)


def clean_runtime_files():
    for path in (SOCKET, PIDFILE):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def start_backend(executable):
    subprocess.Popen(
        [executable],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return wait_for_backend(executable)


def assert_nginx_running():
    for entry in os.listdir("/proc"):
        if entry.isdigit():
            try:
                text = cmdline(int(entry))
                if "nginx" in text and "master process" in text:
                    return
            except Exception:
                pass
    raise AssertionError("Nginx master process is not running.")


def test_complete_restore():
    assert os.path.isfile(SUCCESS), f"File {SUCCESS} is missing."
    assert open(SUCCESS).read().strip() == EXPECTED, "success.txt has incorrect content."

    assert os.path.isfile(SOURCE), f"Backend source {SOURCE} is missing."
    assert os.path.isfile(BINARY), f"Compiled backend {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Compiled backend {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."

    assert_nginx_running()
    nginx_dump = subprocess.run(
        ["nginx", "-T", "-c", ROOT + "/nginx.conf", "-p", ROOT + "/"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=5,
    )
    assert nginx_dump.returncode == 0, f"Nginx configuration is invalid:\n{nginx_dump.stdout}"
    assert re.search(
        r"proxy_pass\s+http://unix:/home/user/restore/run/backend\.sock\s*;",
        nginx_dump.stdout,
    ), "The effective Nginx configuration does not proxy to the required backend socket."

    original_pid = read_pid()
    assert_process_executable(original_pid, BINARY)
    assert_socket_owned_by(original_pid)
    direct_backend_request()
    assert nginx_request() == EXPECTED, "Nginx returned an unexpected response body."

    fd, candidate = tempfile.mkstemp(prefix="backend-source-check-", dir="/tmp")
    os.close(fd)
    os.unlink(candidate)
    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", candidate],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"The submitted backend.c does not compile with gcc:\n{compile_result.stdout}"
    )

    candidate_pid = None
    original_stopped = False
    try:
        stop_process(original_pid)
        original_stopped = True
        clean_runtime_files()

        candidate_pid = start_backend(candidate)
        assert read_pid() == candidate_pid, "The backend compiled from source did not write its own PID."
        direct_backend_request()
        assert nginx_request() == EXPECTED, (
            "Nginx could not communicate with the backend compiled from submitted source."
        )

        # A real proxy request must depend on this backend process. A static Nginx
        # response would continue succeeding while the backend is stopped.
        os.kill(candidate_pid, signal.SIGSTOP)
        static_success = False
        try:
            static_success = nginx_request(timeout=0.5) == EXPECTED
        except Exception:
            pass
        finally:
            os.kill(candidate_pid, signal.SIGCONT)
        assert not static_success, "Nginx serves a fixed response without communicating with the backend."
        assert nginx_request() == EXPECTED, "Service did not recover after resuming the backend."
    finally:
        if candidate_pid is not None:
            try:
                os.kill(candidate_pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
            stop_process(candidate_pid)
        if original_stopped:
            clean_runtime_files()
            restored_pid = start_backend(BINARY)
            assert_process_executable(restored_pid, BINARY)
            assert_socket_owned_by(restored_pid)
            assert nginx_request() == EXPECTED, "Restored compiled backend is not serving through Nginx."
        try:
            os.unlink(candidate)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
