#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import socket
import threading
import time
import shutil
import signal


def test_bashrc_updated():
    """Check that .bashrc contains and actually applies HUB_PORT=8888."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist."
    with open(bashrc_path, "r") as f:
        content = f.read()
    assert "export HUB_PORT=8888" in content, "HUB_PORT=8888 is not exported in .bashrc."

    result = subprocess.run(
        ["bash", "-c", "unset HUB_PORT; source /home/user/.bashrc; printf '__PORT__%s' \"${HUB_PORT-}\""],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, ".bashrc could not be sourced successfully."
    assert result.stdout.endswith("__PORT__8888"), ".bashrc does not actually set HUB_PORT to 8888 when sourced."


def test_heartbeat_files():
    """Check that heartbeat.c and a native executable exist."""
    c_path = "/home/user/heartbeat.c"
    bin_path = "/home/user/heartbeat"
    assert os.path.isfile(c_path), f"{c_path} does not exist."
    assert os.path.isfile(bin_path), f"{bin_path} does not exist."
    st = os.stat(bin_path)
    assert st.st_mode & stat.S_IXUSR, f"{bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not a compiled native executable."


def test_heartbeat_source_compiles():
    """Compile the submitted C source and ensure it produces an executable heartbeat client."""
    output = "/tmp/heartbeat_from_source"
    result = subprocess.run(
        ["gcc", "/home/user/heartbeat.c", "-o", output],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"heartbeat.c does not compile: {result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    with open(output, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    # Exercise the source-built artifact on a port known to have no listener.
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    env = os.environ.copy()
    env["HUB_PORT"] = str(port)
    run = subprocess.run([output], env=env, capture_output=True, text=True, timeout=5)
    assert run.returncode == 1
    assert run.stdout == "CONNECTION_FAILED\n"


def test_heartbeat_execution_fail():
    """Check heartbeat behavior when connection fails."""
    env = os.environ.copy()
    env["HUB_PORT"] = "8888"
    result = subprocess.run(
        ["/home/user/heartbeat"], env=env, capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 1, f"Expected exit code 1, got {result.returncode}"
    assert result.stdout == "CONNECTION_FAILED\n", f"Expected 'CONNECTION_FAILED\\n', got {repr(result.stdout)}"


def test_heartbeat_execution_success():
    """Check heartbeat output, network writes, iteration count, delay, and exit status."""
    env = os.environ.copy()
    env["HUB_PORT"] = "8888"
    received_data = []
    ready = threading.Event()

    def server_thread():
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", 8888))
        s.listen(1)
        s.settimeout(8)
        ready.set()
        try:
            conn, _ = s.accept()
            conn.settimeout(8)
            data = b""
            while True:
                chunk = conn.recv(1024)
                if not chunk:
                    break
                data += chunk
            received_data.append(data)
            conn.close()
        finally:
            s.close()

    t = threading.Thread(target=server_thread)
    t.start()
    assert ready.wait(2), "Test server did not start."

    start = time.monotonic()
    result = subprocess.run(
        ["/home/user/heartbeat"], env=env, capture_output=True, text=True, timeout=9
    )
    elapsed = time.monotonic() - start
    t.join(timeout=9)
    assert not t.is_alive(), "Heartbeat did not close its TCP connection."

    assert result.returncode == 2, f"Expected exit code 2, got {result.returncode}"
    expected_stdout = "HEARTBEAT_SENT\n" * 5
    assert result.stdout == expected_stdout, f"Expected 5x HEARTBEAT_SENT, got {repr(result.stdout)}"
    assert len(received_data) == 1, "Server did not receive data."
    assert received_data[0] == b"PING\n" * 5, f"Expected 5x PING\\n, got {repr(received_data[0])}"
    assert elapsed >= 4.5, f"Heartbeat did not sleep for one second in each iteration ({elapsed:.2f}s total)."


def test_supervisor_files():
    """Check that supervisor.sh exists, is executable, and is a Bash script."""
    script_path = "/home/user/supervisor.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"{script_path} is not executable."
    with open(script_path, "r", errors="replace") as f:
        first_line = f.readline()
    assert first_line.startswith("#!") and "bash" in first_line, "supervisor.sh is not a Bash script."


def test_health_check_files():
    """Check that health_check.sh exists, is executable, and is a Bash script."""
    script_path = "/home/user/health_check.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"{script_path} is not executable."
    with open(script_path, "r", errors="replace") as f:
        first_line = f.readline()
    assert first_line.startswith("#!") and "bash" in first_line, "health_check.sh is not a Bash script."


def test_health_check_behavior():
    """Check FAIL and both permitted OK log locations."""
    os.makedirs("/home/user/logs", exist_ok=True)
    log_file = "/home/user/logs/edge.log"
    old_log_file = "/home/user/logs/edge.log.old"

    for path in (log_file, old_log_file):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(["/home/user/health_check.sh"], capture_output=True, text=True, timeout=5)
    assert result.returncode == 1, "Expected exit code 1 when logs are empty/nonexistent."
    assert "STATUS: FAIL" in result.stdout, "Expected 'STATUS: FAIL' in stdout."

    with open(log_file, "w") as f:
        f.write("CONNECTION_FAILED\nHEARTBEAT_SENT\n")
    result = subprocess.run(["/home/user/health_check.sh"], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, "Expected exit code 0 when HEARTBEAT_SENT is in edge.log."
    assert "STATUS: OK" in result.stdout, "Expected 'STATUS: OK' in stdout."

    os.remove(log_file)
    with open(old_log_file, "w") as f:
        f.write("prefix HEARTBEAT_SENT suffix\n")
    result = subprocess.run(["/home/user/health_check.sh"], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, "Expected exit code 0 when HEARTBEAT_SENT is in edge.log.old."
    assert "STATUS: OK" in result.stdout, "Expected 'STATUS: OK' in stdout."


def _stop_process(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=2)


def _wait_for_calls(path, count, timeout=4):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.exists(path):
            with open(path) as f:
                lines = [line.strip() for line in f if line.strip()]
            if len(lines) >= count:
                return lines
        time.sleep(0.03)
    return []


def test_supervisor_behavior():
    """Exercise creation, append redirection, strict rotation, overwrite, restart, and environment loading."""
    heartbeat = "/home/user/heartbeat"
    backup = "/tmp/original_heartbeat"
    calls = "/tmp/supervisor_calls"
    logs = "/home/user/logs"
    log_file = os.path.join(logs, "edge.log")
    old_log_file = os.path.join(logs, "edge.log.old")
    payload = "123456789\n"  # exactly 10 bytes

    shutil.copy2(heartbeat, backup)
    mock = """#!/bin/bash
printf '%s %s\\n' "$(date +%s.%N)" "${HUB_PORT-}" >> /tmp/supervisor_calls
printf '123456789\\n'
exit 7
"""

    try:
        with open(heartbeat, "w") as f:
            f.write(mock)
        os.chmod(heartbeat, 0o755)

        # The supervisor itself must create logs and redirect heartbeat stdout.
        shutil.rmtree(logs, ignore_errors=True)
        if os.path.exists(calls):
            os.remove(calls)
        proc = subprocess.Popen(
            ["/home/user/supervisor.sh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            lines = _wait_for_calls(calls, 1)
            time.sleep(0.2)
        finally:
            _stop_process(proc)
        assert lines, "Supervisor never executed /home/user/heartbeat."
        assert os.path.isdir(logs), "Supervisor did not create /home/user/logs."
        assert os.path.isfile(log_file), "Supervisor did not redirect heartbeat stdout to edge.log."
        with open(log_file) as f:
            assert f.read() == payload
        assert lines[0].split()[-1] == "8888", "Supervisor did not source .bashrc before starting heartbeat."

        # Exactly 100 bytes must not rotate, and existing content must be preserved by append.
        if os.path.exists(calls):
            os.remove(calls)
        if os.path.exists(old_log_file):
            os.remove(old_log_file)
        with open(log_file, "w") as f:
            f.write("A" * 90)
        proc = subprocess.Popen(
            ["/home/user/supervisor.sh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            lines = _wait_for_calls(calls, 1)
            time.sleep(0.2)
        finally:
            _stop_process(proc)
        assert lines, "Supervisor did not run heartbeat for the threshold test."
        assert not os.path.exists(old_log_file), "Supervisor rotated edge.log at 100 bytes; rotation must be strictly greater than 100."
        with open(log_file) as f:
            assert f.read() == ("A" * 90) + payload, "Heartbeat output was not appended to edge.log."

        # At 105 bytes it must rotate, overwrite an old rotation, sleep, and restart even after exit 7.
        if os.path.exists(calls):
            os.remove(calls)
        with open(log_file, "w") as f:
            f.write("B" * 95)
        with open(old_log_file, "w") as f:
            f.write("STALE_OLD_LOG")
        proc = subprocess.Popen(
            ["/home/user/supervisor.sh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            lines = _wait_for_calls(calls, 2, timeout=5)
            time.sleep(0.2)
        finally:
            _stop_process(proc)
        assert len(lines) >= 2, "Supervisor did not restart heartbeat after it exited with a nonzero status."
        with open(old_log_file) as f:
            assert f.read() == ("B" * 95) + payload, "Supervisor did not correctly rotate and overwrite edge.log.old."
        assert os.path.isfile(log_file), "Restarted heartbeat did not create a new edge.log."
        with open(log_file) as f:
            assert f.read().startswith(payload), "Restarted heartbeat output was not appended to the new edge.log."
        first_time = float(lines[0].split()[0])
        second_time = float(lines[1].split()[0])
        assert second_time - first_time >= 0.8, "Supervisor did not sleep about one second before restarting heartbeat."
        assert all(line.split()[-1] == "8888" for line in lines[:2]), "Restarted heartbeat did not inherit HUB_PORT=8888."
    finally:
        shutil.copy2(backup, heartbeat)
        os.chmod(heartbeat, os.stat(backup).st_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
