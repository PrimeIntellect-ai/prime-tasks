#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import queue
import re
import shlex
import shutil
import socket
import stat
import subprocess
import threading
import time
import uuid

PROJECT = "/home/user/health_checker"
CHECKER = "/home/user/health_checker/target/release/health_checker"
MANAGER = "/home/user/manager.sh"


def test_rust_project_exists():
    assert os.path.isfile(f"{PROJECT}/Cargo.toml"), f"{PROJECT}/Cargo.toml does not exist"
    assert os.path.isfile(f"{PROJECT}/src/main.rs"), f"{PROJECT}/src/main.rs does not exist"


def test_manager_script_exists_and_executable():
    assert os.path.isfile(MANAGER), f"{MANAGER} does not exist"
    st = os.stat(MANAGER)
    assert bool(st.st_mode & stat.S_IXUSR), f"{MANAGER} is not executable"


def start_one_shot_server(response=None, hold_seconds=0):
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]
    listener.listen(1)
    received = queue.Queue()

    def serve():
        try:
            listener.settimeout(5)
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(2)
                data = b""
                while not data.endswith(b"\n") and len(data) < 1024:
                    chunk = conn.recv(1024)
                    if not chunk:
                        break
                    data += chunk
                received.put(data)
                if hold_seconds:
                    time.sleep(hold_seconds)
                elif response is not None:
                    conn.sendall(response)
        finally:
            listener.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    return port, received, thread


def run_checker(port, timeout=7):
    start = time.monotonic()
    result = subprocess.run(
        [CHECKER, str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    return result, time.monotonic() - start


def test_health_checker_behavior():
    subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert os.path.isfile(CHECKER), f"compiled checker {CHECKER} does not exist"
    assert os.access(CHECKER, os.X_OK), f"compiled checker {CHECKER} is not executable"

    port, received, thread = start_one_shot_server(b"PONG\n")
    result, _ = run_checker(port)
    thread.join(timeout=2)
    assert received.get(timeout=1) == b"PING\n", "health checker did not send exactly PING\\n"
    assert result.returncode == 0, f"healthy response returned {result.returncode}: {result.stderr}"
    assert result.stdout == "HEALTHY\n", f"unexpected healthy output: {result.stdout!r}"

    bad_response = ("BAD-" + uuid.uuid4().hex + "\n").encode()
    port, received, thread = start_one_shot_server(bad_response)
    result, _ = run_checker(port)
    thread.join(timeout=2)
    assert received.get(timeout=1) == b"PING\n", "health checker did not send exactly PING\\n"
    assert result.returncode == 1, f"invalid response returned {result.returncode} instead of 1"
    assert result.stdout == "UNHEALTHY\n", f"unexpected invalid-response output: {result.stdout!r}"

    port, received, thread = start_one_shot_server(b"PONG\nEXTRA")
    result, _ = run_checker(port)
    thread.join(timeout=2)
    assert received.get(timeout=1) == b"PING\n", "health checker did not send exactly PING\\n"
    assert result.returncode == 1, "a response other than exactly PONG\\n was accepted"
    assert result.stdout == "UNHEALTHY\n"

    unused = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    unused.bind(("127.0.0.1", 0))
    closed_port = unused.getsockname()[1]
    unused.close()
    result, _ = run_checker(closed_port)
    assert result.returncode == 1, "connection failure did not return status 1"
    assert result.stdout == "UNHEALTHY\n"

    port, received, _ = start_one_shot_server(response=None, hold_seconds=5)
    result, elapsed = run_checker(port)
    assert received.get(timeout=1) == b"PING\n", "health checker did not send exactly PING\\n"
    assert result.returncode == 1, "read timeout did not return status 1"
    assert result.stdout == "UNHEALTHY\n"
    assert elapsed < 4.5, f"health checker did not time out gracefully (elapsed {elapsed:.2f}s)"


def test_integration_manager_script():
    subprocess.run(["pkill", "-f", "socat TCP-LISTEN:8080"], capture_output=True)
    for path in ("/home/user/proxy.pid", "/home/user/monitoring.log"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    mock_server = subprocess.Popen(
        ["socat", "TCP-LISTEN:9090,fork,reuseaddr", "SYSTEM:echo -ne 'PONG\\n'"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    manager_proc = None
    token = uuid.uuid4().hex
    marker = f"/tmp/checker-invocations-{token}"
    force_failure = f"/tmp/checker-force-failure-{token}"
    saved_checker = f"/tmp/real-health-checker-{token}"

    try:
        time.sleep(1)
        manager_proc = subprocess.Popen(
            [MANAGER],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        pid_file = "/home/user/proxy.pid"
        deadline = time.time() + 60
        while time.time() < deadline and not os.path.exists(pid_file):
            if manager_proc.poll() is not None:
                break
            time.sleep(0.2)
        assert os.path.exists(pid_file), "proxy.pid was not created within the timeout (compilation might have failed or script is stuck)"
        assert manager_proc.poll() is None, "manager.sh exited before monitoring began"
        assert os.path.isfile(CHECKER) and os.access(CHECKER, os.X_OK), "manager did not build the release health checker"

        shutil.copy2(CHECKER, saved_checker)
        wrapper_tmp = f"{CHECKER}.verifier-{token}"
        wrapper = (
            "#!/bin/bash\n"
            f"echo invoked >> {shlex.quote(marker)}\n"
            f"if [ -e {shlex.quote(force_failure)} ]; then\n"
            "  echo UNHEALTHY\n"
            "  exit 1\n"
            "fi\n"
            f"exec {shlex.quote(saved_checker)} \"$@\"\n"
        )
        with open(wrapper_tmp, "w") as f:
            f.write(wrapper)
        os.chmod(wrapper_tmp, 0o755)
        os.replace(wrapper_tmp, CHECKER)

        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(marker):
            time.sleep(0.1)
        assert os.path.exists(marker), "manager.sh did not execute the compiled Rust health checker"

        log_file = "/home/user/monitoring.log"
        deadline = time.time() + 3
        while time.time() < deadline:
            if os.path.exists(log_file) and "HEALTHY" in open(log_file).read():
                break
            time.sleep(0.1)
        assert os.path.exists(log_file), "monitoring.log was not created"
        with open(log_file) as f:
            log_content = f.read()
        assert "HEALTHY" in log_content, "monitoring.log does not contain HEALTHY"

        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=2) as s:
                s.sendall(b"PING\n")
                data = s.recv(1024)
                assert b"PONG" in data, "Did not receive PONG from forwarded port 8080"
        except Exception as e:
            assert False, f"Failed to connect to forwarded port 8080: {e}"

        # Trigger an unpredictable checker failure while the backend remains healthy.
        # This proves the manager uses the checker's actual exit status rather than a fixed delay.
        with open(force_failure, "w") as f:
            f.write(token)

        deadline = time.time() + 5
        while time.time() < deadline and manager_proc.poll() is None:
            time.sleep(0.1)
        assert manager_proc.poll() is not None, "manager.sh did not exit after health check failure"

        mock_server.terminate()
        mock_server.wait(timeout=5)

        with open(pid_file) as f:
            proxy_pid_str = f.read().strip()
        assert proxy_pid_str.isdigit(), f"Invalid PID in proxy.pid: {proxy_pid_str}"
        proxy_pid = int(proxy_pid_str)

        process_alive = False
        try:
            os.kill(proxy_pid, 0)
            process_alive = True
        except OSError:
            pass
        assert not process_alive, f"socat proxy process (PID {proxy_pid}) is still running after health check failure"

        retcode = manager_proc.poll()
        assert retcode is not None, "manager.sh did not exit after health check failure"
        assert retcode != 0, f"manager.sh exited with code {retcode}, expected non-zero (1)"

        with open(log_file) as f:
            log_content = f.read()
        assert "UNHEALTHY" in log_content, "monitoring.log does not contain UNHEALTHY after failure"
        nonempty_lines = [line for line in log_content.splitlines() if line.strip()]
        assert any(re.fullmatch(r"\d+ HEALTHY", line) for line in nonempty_lines), "no correctly formatted HEALTHY log entry"
        assert any(re.fullmatch(r"\d+ UNHEALTHY", line) for line in nonempty_lines), "no correctly formatted UNHEALTHY log entry"

    finally:
        if mock_server.poll() is None:
            mock_server.kill()
            mock_server.wait(timeout=5)
        if manager_proc and manager_proc.poll() is None:
            manager_proc.kill()
            manager_proc.wait(timeout=5)
        subprocess.run(["pkill", "-f", "socat TCP-LISTEN:8080"], capture_output=True)
        for path in (marker, force_failure, saved_checker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
