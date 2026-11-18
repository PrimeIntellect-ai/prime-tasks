#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import tempfile
import time


def test_cpp_source_exists():
    """Verify that the C++ source file exists."""
    cpp_path = "/home/user/src/tcp_ping.cpp"
    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} does not exist."


def test_bash_script_exists_and_executable():
    """Verify that the bash script exists and is executable."""
    script_path = "/home/user/run_checks.sh"
    assert os.path.isfile(script_path), f"Bash script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Bash script {script_path} is not executable."


def test_binary_exists_and_executable():
    """Verify that the compiled C++ binary exists and is executable."""
    bin_path = "/home/user/bin/tcp_ping"
    assert os.path.isfile(bin_path), f"Compiled binary {bin_path} does not exist."
    assert os.access(bin_path, os.X_OK), f"Compiled binary {bin_path} is not executable."


def test_uptime_log_contents():
    """Verify that the uptime.log file contains exactly the expected UP and DOWN sequence."""
    log_path = "/home/user/uptime.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "UP\nDOWN"
    assert content == expected_content, f"Log file contents do not match expected sequence. Expected:\n{expected_content}\nActual:\n{content}"


def port_is_open(port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(0.2)
    try:
        return sock.connect_ex(("127.0.0.1", port)) == 0
    finally:
        sock.close()


def run_ping(binary, port, expected):
    result = subprocess.run(
        [binary, str(port)], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == expected + "\n", (
        f"{binary} returned {result.stdout!r} for port {port}; expected {expected!r}"
    )


def exercise_ping(binary):
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    open_port = listener.getsockname()[1]
    try:
        run_ping(binary, open_port, "UP")
    finally:
        listener.close()

    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    closed_port = probe.getsockname()[1]
    probe.close()
    assert not port_is_open(closed_port)
    run_ping(binary, closed_port, "DOWN")

    no_args = subprocess.run([binary], capture_output=True, text=True, timeout=5)
    too_many = subprocess.run(
        [binary, str(closed_port), str(closed_port)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert no_args.returncode != 0, "tcp_ping must reject a missing port argument"
    assert too_many.returncode != 0, "tcp_ping must reject extra arguments"


def test_orchestration_script_recreates_and_runs_artifacts():
    assert not port_is_open(8888), "TCP port 8888 is already occupied before the script runs"

    for path in ("/home/user/bin/tcp_ping", "/home/user/uptime.log"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    proc = subprocess.Popen(
        ["/home/user/run_checks.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    saw_listener = False
    deadline = time.time() + 15
    try:
        while time.time() < deadline and proc.poll() is None:
            if port_is_open(8888):
                saw_listener = True
                break
            time.sleep(0.05)
        stdout, stderr = proc.communicate(timeout=30)
    except Exception:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
        raise

    assert proc.returncode == 0, f"run_checks.sh failed:\nstdout:\n{stdout}\nstderr:\n{stderr}"
    assert saw_listener, "run_checks.sh never started a TCP listener on port 8888"
    assert not port_is_open(8888), "run_checks.sh did not shut down the service on port 8888"

    binary = "/home/user/bin/tcp_ping"
    assert os.path.isfile(binary), "run_checks.sh did not recreate /home/user/bin/tcp_ping"
    assert os.access(binary, os.X_OK), "recreated tcp_ping is not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "tcp_ping is not a compiled native executable"

    with open("/home/user/uptime.log", "r") as f:
        assert f.read() == "UP\nDOWN\n", "fresh orchestration run did not record UP then DOWN"


def test_submitted_binary_and_cpp_source_behaviour():
    exercise_ping("/home/user/bin/tcp_ping")

    fd, compiled = tempfile.mkstemp(prefix="tcp_ping_from_source_")
    os.close(fd)
    os.remove(compiled)
    try:
        result = subprocess.run(
            ["g++", "/home/user/src/tcp_ping.cpp", "-o", compiled],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"C++ source does not compile:\n{result.stderr}"
        exercise_ping(compiled)
    finally:
        try:
            os.remove(compiled)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
