#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import socket
import subprocess
import tempfile
import threading
import time
import pytest

DAEMON_C = "/home/user/account_daemon.c"
DAEMON_BIN = "/home/user/account_daemon"
SERVICE_SH = "/home/user/service.sh"
PID_FILE = "/home/user/account_daemon.pid"
SOCK_FILE = "/home/user/account.sock"
EXPECT_SCRIPT = "/home/user/health_check.exp"
MONITOR_SCRIPT = "/home/user/monitor.sh"
HEALTH_LOG = "/home/user/health.log"


def wait_for_socket(timeout=3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if stat.S_ISSOCK(os.stat(SOCK_FILE).st_mode):
                return
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    pytest.fail(f"Socket {SOCK_FILE} did not become ready.")


def start_service():
    subprocess.run(["bash", SERVICE_SH, "start"], check=True, timeout=5)
    wait_for_socket()


def stop_service():
    subprocess.run(["bash", SERVICE_SH, "stop"], check=True, timeout=5)
    time.sleep(0.2)


def check_protocol(sock_path=SOCK_FILE, include_quit=False):
    # Wrong password.
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect(sock_path)
        data = s.recv(1024)
        assert data == b"PASSWD:\n", f"Expected 'PASSWD:\\n', got {data!r}"
        s.sendall(b"wrongpass\n")
        data = s.recv(1024)
        assert data == b"DENIED\n", f"Expected 'DENIED\\n', got {data!r}"
    finally:
        s.close()

    # Correct password and PING.
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect(sock_path)
        data = s.recv(1024)
        assert data == b"PASSWD:\n", f"Expected 'PASSWD:\\n', got {data!r}"
        s.sendall(b"adminpass\n")
        data = s.recv(1024)
        assert data == b"AUTH_OK\n", f"Expected 'AUTH_OK\\n', got {data!r}"
        s.sendall(b"PING\n")
        data = s.recv(1024)
        assert data == b"PONG\n", f"Expected 'PONG\\n', got {data!r}"
    finally:
        s.close()

    if include_quit:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(2.0)
        try:
            s.connect(sock_path)
            assert s.recv(1024) == b"PASSWD:\n"
            s.sendall(b"adminpass\n")
            assert s.recv(1024) == b"AUTH_OK\n"
            s.sendall(b"QUIT\n")
            assert s.recv(1024) == b"", "Daemon did not close after QUIT."
        finally:
            s.close()


def test_daemon_files_exist():
    """Verify that the C file and compiled binary exist and are correct."""
    assert os.path.isfile(DAEMON_C), f"C source file {DAEMON_C} is missing."
    assert os.path.isfile(DAEMON_BIN), f"Compiled binary {DAEMON_BIN} is missing."
    st = os.stat(DAEMON_BIN)
    assert bool(st.st_mode & stat.S_IXUSR), f"Binary {DAEMON_BIN} is not executable."
    with open(DAEMON_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{DAEMON_BIN} is not a compiled ELF binary."


def test_daemon_running():
    """Verify that the daemon is currently running and socket exists."""
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} is missing."
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {PID_FILE} does not contain a valid PID."
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} from {PID_FILE} is not running.")
    assert os.path.exists(SOCK_FILE), f"Socket file {SOCK_FILE} is missing."
    st = os.stat(SOCK_FILE)
    assert stat.S_ISSOCK(st.st_mode), f"{SOCK_FILE} is not a socket."


def test_c_source_compiles_and_implements_protocol():
    """Compile and execute the submitted C source rather than trusting another daemon."""
    fd, compiled = tempfile.mkstemp(prefix="account_daemon_from_source_")
    os.close(fd)
    os.unlink(compiled)
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", DAEMON_C, "-o", compiled],
        capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"C source did not compile:\n{result.stdout}\n{result.stderr}"
    with open(compiled, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    proc = None
    stop_service()
    try:
        if os.path.lexists(SOCK_FILE):
            os.unlink(SOCK_FILE)
        proc = subprocess.Popen([compiled], start_new_session=True,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_for_socket()
        check_protocol(include_quit=True)
    finally:
        if proc is not None:
            try:
                os.killpg(proc.pid, 15)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, 9)
                except ProcessLookupError:
                    pass
        if os.path.lexists(SOCK_FILE):
            os.unlink(SOCK_FILE)
        if os.path.exists(compiled):
            os.unlink(compiled)
        start_service()


def test_daemon_protocol():
    """Verify the daemon protocol over the Unix socket."""
    check_protocol(include_quit=True)


def test_expect_script():
    """Verify the Expect script works and exits with 0."""
    assert os.path.isfile(EXPECT_SCRIPT), f"Expect script {EXPECT_SCRIPT} missing."
    result = subprocess.run(["expect", EXPECT_SCRIPT], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"Expect script failed with exit code {result.returncode}. "
        f"Output: {result.stdout} {result.stderr}"
    )


def run_fake_server_case(mode):
    if os.path.lexists(SOCK_FILE):
        os.unlink(SOCK_FILE)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCK_FILE)
    server.listen(1)
    server.settimeout(10)
    errors = []

    def serve():
        try:
            conn, _ = server.accept()
            with conn:
                conn.settimeout(3)
                if mode == "bad_prompt":
                    conn.sendall(b"NOT_A_PASSWORD_PROMPT\n")
                    return
                conn.sendall(b"PASSWD:\n")
                password = conn.recv(1024)
                if password != b"adminpass\n":
                    errors.append(f"Expected adminpass, got {password!r}")
                    return
                if mode == "bad_auth":
                    conn.sendall(b"DENIED\n")
                    return
                conn.sendall(b"AUTH_OK\n")
                ping = conn.recv(1024)
                if ping != b"PING\n":
                    errors.append(f"Expected PING, got {ping!r}")
                    return
                conn.sendall(b"NOT_PONG\n")
        except Exception as exc:
            errors.append(repr(exc))

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    try:
        result = subprocess.run(["expect", EXPECT_SCRIPT], capture_output=True,
                                text=True, timeout=10)
    finally:
        server.close()
        thread.join(timeout=2)
        if os.path.lexists(SOCK_FILE):
            os.unlink(SOCK_FILE)
    assert not errors, f"Health check did not perform the expected exchange: {errors}"
    assert result.returncode != 0, (
        f"Health check incorrectly succeeded for server case {mode}. "
        f"Output: {result.stdout} {result.stderr}"
    )


def test_expect_script_rejects_protocol_failures():
    """Ensure the health checker actually checks every required protocol stage."""
    stop_service()
    try:
        for mode in ("bad_prompt", "bad_auth", "bad_pong"):
            run_fake_server_case(mode)
    finally:
        if os.path.lexists(SOCK_FILE):
            os.unlink(SOCK_FILE)
        start_service()


def test_monitor_script():
    """Verify the monitor script appends HEALTHY to the log."""
    assert os.path.isfile(MONITOR_SCRIPT), f"Monitor script {MONITOR_SCRIPT} missing."
    lines_before = []
    if os.path.isfile(HEALTH_LOG):
        with open(HEALTH_LOG, "r") as f:
            lines_before = f.readlines()
    result = subprocess.run(["bash", MONITOR_SCRIPT], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Monitor script failed with exit code {result.returncode}."
    assert os.path.isfile(HEALTH_LOG), f"Health log {HEALTH_LOG} was not created."
    with open(HEALTH_LOG, "r") as f:
        lines_after = f.readlines()
    assert len(lines_after) == len(lines_before) + 1, "Monitor script did not append exactly one line to the log."
    assert lines_after[-1].strip() == "HEALTHY", f"Expected 'HEALTHY' in log, got {lines_after[-1].strip()!r}"


def test_monitor_script_unhealthy_branch():
    """Verify monitor output is determined by the health check's failure status."""
    backup = EXPECT_SCRIPT + ".verifier_backup"
    assert not os.path.exists(backup)
    os.replace(EXPECT_SCRIPT, backup)
    try:
        with open(EXPECT_SCRIPT, "w") as f:
            f.write("#!/bin/sh\nexit 1\n")
        os.chmod(EXPECT_SCRIPT, 0o755)
        lines_before = []
        if os.path.isfile(HEALTH_LOG):
            with open(HEALTH_LOG, "r") as f:
                lines_before = f.readlines()
        result = subprocess.run(["bash", MONITOR_SCRIPT], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Monitor script failed with exit code {result.returncode}."
        with open(HEALTH_LOG, "r") as f:
            lines_after = f.readlines()
        assert len(lines_after) == len(lines_before) + 1, "Monitor did not append exactly one failure result."
        assert lines_after[-1].strip() == "UNHEALTHY", (
            f"Expected 'UNHEALTHY' for a failed health check, got {lines_after[-1].strip()!r}"
        )
    finally:
        if os.path.exists(EXPECT_SCRIPT):
            os.unlink(EXPECT_SCRIPT)
        os.replace(backup, EXPECT_SCRIPT)


def test_service_script():
    """Verify the service script can stop and start the daemon cleanly."""
    assert os.path.isfile(SERVICE_SH), f"Service script {SERVICE_SH} missing."
    subprocess.run(["bash", SERVICE_SH, "stop"], check=True)
    time.sleep(0.5)
    assert not os.path.exists(PID_FILE), f"PID file {PID_FILE} should be deleted after stop."
    assert not os.path.exists(SOCK_FILE), f"Socket file {SOCK_FILE} should be deleted after stop."
    subprocess.run(["bash", SERVICE_SH, "start"], check=True)
    time.sleep(0.5)
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} should be created after start."
    assert os.path.exists(SOCK_FILE), f"Socket file {SOCK_FILE} should be created after start."
    assert stat.S_ISSOCK(os.stat(SOCK_FILE).st_mode), f"{SOCK_FILE} is not a socket after restart."
    check_protocol(include_quit=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
