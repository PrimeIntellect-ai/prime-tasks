#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import subprocess
import threading
import time
import pytest

APP_DIR = "/home/user/app"
CONFIG_FILE = os.path.join(APP_DIR, "config.env")
SERVER_SRC = os.path.join(APP_DIR, "server.cpp")
CLIENT_SRC = os.path.join(APP_DIR, "client.cpp")
SERVER_BIN = os.path.join(APP_DIR, "server")
CLIENT_BIN = os.path.join(APP_DIR, "client")
MONITOR_SCRIPT = os.path.join(APP_DIR, "monitor.sh")
SERVER_LOG = os.path.join(APP_DIR, "server.log")
ROTATED_LOG = os.path.join(APP_DIR, "archive/server_rotated.log")
HEALTH_LOG = os.path.join(APP_DIR, "health.log")


def write_config(server_ip, server_port, client_ip, client_port):
    with open(CONFIG_FILE, "w") as f:
        f.write(
            f"SERVER_BIND_IP={server_ip}\n"
            f"SERVER_PORT={server_port}\n"
            f"CLIENT_TARGET_IP={client_ip}\n"
            f"CLIENT_PORT={client_port}\n"
        )


def exact_server_pids():
    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        exe = f"/proc/{name}/exe"
        try:
            if os.path.samefile(exe, SERVER_BIN):
                result.append(int(name))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return result


def free_port(ip="127.0.0.2"):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind((ip, 0))
    port = s.getsockname()[1]
    s.close()
    return port


def wait_for_file_text(path, text, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(path, "r") as f:
                if text in f.read():
                    return
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    pytest.fail(f"Timed out waiting for {text!r} in {path}")


def test_config_env():
    assert os.path.isfile(CONFIG_FILE), f"{CONFIG_FILE} is missing."
    with open(CONFIG_FILE, "r") as f:
        content = f.read()
    assert "CLIENT_TARGET_IP=127.0.0.2" in content, "CLIENT_TARGET_IP is not correctly set to 127.0.0.2 in config.env"
    assert "CLIENT_PORT=8888" in content, "CLIENT_PORT is not correctly set to 8888 in config.env"
    assert "SERVER_BIND_IP=127.0.0.2" in content, "SERVER_BIND_IP should remain 127.0.0.2"
    assert "SERVER_PORT=8888" in content, "SERVER_PORT should remain 8888"


def test_binaries_compiled():
    assert os.path.isfile(SERVER_BIN), f"Server binary {SERVER_BIN} is missing. Did you compile it?"
    assert os.access(SERVER_BIN, os.X_OK), f"Server binary {SERVER_BIN} is not executable."
    assert os.path.isfile(CLIENT_BIN), f"Client binary {CLIENT_BIN} is missing. Did you compile it?"
    assert os.access(CLIENT_BIN, os.X_OK), f"Client binary {CLIENT_BIN} is not executable."

    for binary, source in ((SERVER_BIN, SERVER_SRC), (CLIENT_BIN, CLIENT_SRC)):
        with open(binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{binary} is not a compiled ELF executable."
        assert os.path.getmtime(binary) >= os.path.getmtime(source), f"{binary} predates its supplied source file."

    subprocess.run(["g++", "-fsyntax-only", SERVER_SRC], cwd=APP_DIR, check=True, timeout=20)
    subprocess.run(["g++", "-fsyntax-only", CLIENT_SRC], cwd=APP_DIR, check=True, timeout=20)


def test_server_running():
    try:
        output = subprocess.check_output(["pgrep", "-f", "./server"]).decode()
        assert output.strip(), "Server process is not running."
    except subprocess.CalledProcessError:
        pytest.fail("Server process is not running. pgrep did not find it.")
    assert exact_server_pids(), "No running process actually executes /home/user/app/server."


def test_monitor_script_exists_and_executable():
    assert os.path.isfile(MONITOR_SCRIPT), f"Monitor script {MONITOR_SCRIPT} is missing."
    assert os.access(MONITOR_SCRIPT, os.X_OK), f"Monitor script {MONITOR_SCRIPT} is not executable."
    subprocess.run(["bash", "-n", MONITOR_SCRIPT], check=True)


def test_rotated_log():
    assert os.path.isfile(ROTATED_LOG), f"Rotated log {ROTATED_LOG} is missing. Did the monitor script run?"
    with open(ROTATED_LOG, "r") as f:
        content = f.read()
    assert "Server started on 127.0.0.2:8888" in content, f"Expected startup message not found in {ROTATED_LOG}."


def test_server_log_truncated_and_appended():
    assert os.path.isfile(SERVER_LOG), f"Server log {SERVER_LOG} is missing."
    with open(SERVER_LOG, "r") as f:
        content = f.read()
    assert "Health check received." in content, f"Expected health check message not found in {SERVER_LOG}."
    assert "Server started on" not in content, f"Original startup message should have been truncated from {SERVER_LOG}."


def test_health_log():
    assert os.path.isfile(HEALTH_LOG), f"Health log {HEALTH_LOG} is missing."
    with open(HEALTH_LOG, "r") as f:
        content = f.read()
    assert "HEALTH_OK" in content, f"Expected 'HEALTH_OK' not found in {HEALTH_LOG}."


def test_client_binary_uses_dynamic_configuration_and_network():
    original = open(CONFIG_FILE, "rb").read()
    port = free_port()
    marker = "VERIFIER_" + secrets.token_hex(16) + "\n"
    accepted = threading.Event()
    errors = []

    def mock_server():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                listener.bind(("127.0.0.2", port))
                listener.listen(1)
                listener.settimeout(5)
                conn, _ = listener.accept()
                with conn:
                    accepted.set()
                    conn.sendall(marker.encode())
        except Exception as exc:
            errors.append(exc)

    thread = threading.Thread(target=mock_server, daemon=True)
    thread.start()
    try:
        write_config("127.0.0.2", 8888, "127.0.0.2", port)
        result = subprocess.run([CLIENT_BIN], cwd=APP_DIR, capture_output=True, text=True, timeout=8)
        thread.join(6)
        assert not errors, f"Verifier mock server failed: {errors}"
        assert accepted.is_set(), "The client binary did not connect to its configured endpoint."
        assert result.returncode == 0, result.stderr
        assert result.stdout == marker, "The client did not relay the verifier-generated server response."
    finally:
        with open(CONFIG_FILE, "wb") as f:
            f.write(original)


def test_server_binary_uses_dynamic_configuration_and_serves_health():
    original = open(CONFIG_FILE, "rb").read()
    port = free_port()
    proc = None
    try:
        write_config("127.0.0.2", port, "127.0.0.2", 8888)
        try:
            os.remove(SERVER_LOG)
        except FileNotFoundError:
            pass
        proc = subprocess.Popen([SERVER_BIN], cwd=APP_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        startup = f"Server started on 127.0.0.2:{port}"
        wait_for_file_text(SERVER_LOG, startup)
        assert proc.poll() is None, "The submitted server exited instead of remaining active."
        assert os.path.samefile(f"/proc/{proc.pid}/exe", SERVER_BIN)

        with socket.create_connection(("127.0.0.2", port), timeout=5) as conn:
            response = conn.recv(1024)
        assert response == b"HEALTH_OK\n", "The server did not return the response implemented by server.cpp."
        wait_for_file_text(SERVER_LOG, "Health check received.")
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(3)
        with open(CONFIG_FILE, "wb") as f:
            f.write(original)


def test_monitor_executes_process_check_rotation_and_client():
    assert exact_server_pids(), "The genuine server stopped before monitor testing."
    script_text = open(MONITOR_SCRIPT, "r").read()

    # For the common unqualified pgrep implementation, force its process check
    # to report no server and verify that the script exits with status 1 before
    # touching any logs.
    if re.search(r"(^|[;&|()[:space:]])pgrep([[:space:]]|$)", script_text, re.MULTILINE):
        fake_dir = "/tmp/verifier-no-server"
        os.makedirs(fake_dir, exist_ok=True)
        fake_pgrep = os.path.join(fake_dir, "pgrep")
        with open(fake_pgrep, "w") as f:
            f.write("#!/bin/sh\nexit 1\n")
        os.chmod(fake_pgrep, 0o755)
        absent_server = "NO_SERVER_" + secrets.token_hex(8) + "\n"
        absent_rotated = "OLD_ROTATED_" + secrets.token_hex(8) + "\n"
        absent_health = "OLD_HEALTH_" + secrets.token_hex(8) + "\n"
        open(SERVER_LOG, "w").write(absent_server)
        open(ROTATED_LOG, "w").write(absent_rotated)
        open(HEALTH_LOG, "w").write(absent_health)
        env = os.environ.copy()
        env["PATH"] = fake_dir + os.pathsep + env.get("PATH", "")
        result = subprocess.run([MONITOR_SCRIPT], cwd=APP_DIR, env=env, timeout=8)
        assert result.returncode == 1, "monitor.sh must exit with status 1 when its server check fails."
        assert open(SERVER_LOG).read() == absent_server
        assert open(ROTATED_LOG).read() == absent_rotated
        assert open(HEALTH_LOG).read() == absent_health

    rotation_marker = "ROTATE_" + secrets.token_hex(20) + "\n"
    prior_health = "PRIOR_HEALTH_" + secrets.token_hex(12) + "\n"
    with open(SERVER_LOG, "w") as f:
        f.write(rotation_marker)
    with open(HEALTH_LOG, "w") as f:
        f.write(prior_health)
    try:
        os.remove(ROTATED_LOG)
    except FileNotFoundError:
        pass

    result = subprocess.run([MONITOR_SCRIPT], cwd=APP_DIR, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"monitor.sh failed when the genuine server was running: {result.stderr}"
    assert open(ROTATED_LOG).read() == rotation_marker, "monitor.sh did not copy the exact pre-rotation log contents."
    server_after = open(SERVER_LOG).read()
    assert rotation_marker not in server_after, "monitor.sh did not truncate server.log."
    assert "Health check received." in server_after, "The monitor did not cause its client to reach the server."
    health_after = open(HEALTH_LOG).read()
    assert health_after.startswith(prior_health), "monitor.sh overwrote health.log instead of appending to it."
    assert "HEALTH_OK" in health_after, "monitor.sh did not append the client's actual output."
    assert exact_server_pids(), "monitor.sh did not leave the genuine server running."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
