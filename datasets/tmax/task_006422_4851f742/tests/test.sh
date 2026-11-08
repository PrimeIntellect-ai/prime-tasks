#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any copy left running by the agent so verification controls the services.
pkill -f '^python3 /home/user/mock_services.py$' 2>/dev/null || true
sleep 0.2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import threading
import time


def run(cmd, **kwargs):
    return subprocess.run(cmd, timeout=5, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, **kwargs)


def test_health_check_binary_exists_and_executable():
    """Verify that the compiled C++ monitor exists and is executable."""
    binary_path = "/home/user/bin/health_check"
    assert os.path.isfile(binary_path), f"Binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary_path} is not a compiled ELF binary."


def test_health_check_source_exists():
    source_path = "/home/user/health_check.cpp"
    assert os.path.isfile(source_path), f"{source_path} does not exist."
    assert os.path.getsize(source_path) > 0, f"{source_path} is empty."


def test_env_blue_sh_exists_and_correct():
    """Verify env_blue.sh exists and exports the correct port."""
    env_path = "/home/user/env_blue.sh"
    assert os.path.isfile(env_path), f"{env_path} does not exist."
    with open(env_path, "r") as f:
        content = f.read()
    assert re.search(r"export\s+HEALTH_PORT\s*=\s*[\"']?9001[\"']?", content), f"{env_path} does not properly export HEALTH_PORT=9001."


def test_env_green_sh_exists_and_correct():
    """Verify env_green.sh exists and exports the correct port."""
    env_path = "/home/user/env_green.sh"
    assert os.path.isfile(env_path), f"{env_path} does not exist."
    with open(env_path, "r") as f:
        content = f.read()
    assert re.search(r"export\s+HEALTH_PORT\s*=\s*[\"']?9002[\"']?", content), f"{env_path} does not properly export HEALTH_PORT=9002."


def test_deploy_monitor_sh_exists_and_executable():
    """Verify deploy_monitor.sh exists and is executable."""
    script_path = "/home/user/deploy_monitor.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_deployment_alerts_log():
    """Verify the contents of deployment_alerts.log."""
    log_path = "/home/user/deployment_alerts.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did you run the deploy_monitor.sh script?"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_blue = "[INFO] Deployment blue healthy on port 9001"
    expected_green = "[CRITICAL] Deployment green failed network check on port 9002"

    assert any(expected_blue in line for line in lines), f"Log does not contain expected success message for blue. Found: {lines}"
    assert any(expected_green in line for line in lines), f"Log does not contain expected failure message for green. Found: {lines}"


def exercise_monitor(response, expected_code):
    received = []
    ready = threading.Event()
    port_holder = []

    def server():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("127.0.0.1", 0))
            port_holder.append(s.getsockname()[1])
            s.listen(1)
            ready.set()
            conn, _ = s.accept()
            with conn:
                conn.settimeout(2)
                data = b""
                while not data.endswith(b"\n") and len(data) < 1024:
                    chunk = conn.recv(1024)
                    if not chunk:
                        break
                    data += chunk
                received.append(data)
                conn.sendall(response)

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    assert ready.wait(2), "Test TCP server did not start."
    env = os.environ.copy()
    env["HEALTH_PORT"] = str(port_holder[0])
    result = run(["/home/user/bin/health_check"], env=env)
    thread.join(2)
    assert received == [b"STATUS_REQ\n"], f"Monitor sent the wrong request: {received}"
    assert result.returncode == expected_code, (
        f"Monitor returned {result.returncode} for response {response!r}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def wait_for_port(port):
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f"Mock service on port {port} did not start.")


def read_log():
    with open("/home/user/deployment_alerts.log", "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_z_monitor_and_wrapper_behavior():
    # Exercise the compiled monitor against independently created endpoints.
    exercise_monitor(b"OK\n", 0)
    exercise_monitor(b"ERROR\n", 1)
    exercise_monitor(b"OK\nEXTRA", 1)
    exercise_monitor(b"OK", 1)

    # A refused connection must fail rather than report healthy or hang.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        unused_port = s.getsockname()[1]
    env = os.environ.copy()
    env["HEALTH_PORT"] = str(unused_port)
    refused = run(["/home/user/bin/health_check"], env=env)
    assert refused.returncode == 1, "Monitor did not fail for a refused connection."

    # Replace the binary briefly with a probe to prove that the wrapper sources
    # each profile, invokes the required path, and handles both return codes.
    binary = "/home/user/bin/health_check"
    saved = "/home/user/bin/health_check.verifier-real"
    calls = "/tmp/health_probe_calls"
    if os.path.exists(calls):
        os.unlink(calls)
    os.replace(binary, saved)
    try:
        with open(binary, "w") as f:
            f.write("#!/bin/bash\nprintf '%s\\n' \"${HEALTH_PORT-UNSET}\" >> /tmp/health_probe_calls\ncase \"${HEALTH_PORT-}\" in\n  9001) exit 0 ;;\n  9002) exit 1 ;;\n  *) exit 7 ;;\nesac\n")
        os.chmod(binary, 0o755)

        assert run(["/home/user/deploy_monitor.sh"]).returncode != 0, "Wrapper accepted no arguments."
        assert run(["/home/user/deploy_monitor.sh", "blue", "green"]).returncode != 0, "Wrapper accepted more than one argument."
        assert run(["/home/user/deploy_monitor.sh", "red"]).returncode != 0, "Wrapper accepted an invalid environment."

        open("/home/user/deployment_alerts.log", "w").close()
        blue = run(["/home/user/deploy_monitor.sh", "blue"])
        green = run(["/home/user/deploy_monitor.sh", "green"])
        assert blue.returncode == 0, f"Blue wrapper run failed: {blue.stderr}"
        assert green.returncode == 0, f"Monitor failure crashed the wrapper: {green.stderr}"
        with open(calls, "r") as f:
            assert f.read().splitlines() == ["9001", "9002"], "Wrapper did not invoke the monitor with sourced ports."
        assert read_log() == [
            "[INFO] Deployment blue healthy on port 9001",
            "[CRITICAL] Deployment green failed network check on port 9002",
        ]
    finally:
        if os.path.exists(binary):
            os.unlink(binary)
        os.replace(saved, binary)

    # Finally run the submitted wrapper and real binary against the supplied mocks.
    mock = subprocess.Popen(["python3", "/home/user/mock_services.py"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_port(9001)
        wait_for_port(9002)
        open("/home/user/deployment_alerts.log", "w").close()
        blue = run(["/home/user/deploy_monitor.sh", "blue"])
        green = run(["/home/user/deploy_monitor.sh", "green"])
        assert blue.returncode == 0, f"Blue integration run failed: {blue.stderr}"
        assert green.returncode == 0, f"Green integration run crashed: {green.stderr}"
        assert read_log() == [
            "[INFO] Deployment blue healthy on port 9001",
            "[CRITICAL] Deployment green failed network check on port 9002",
        ]
    finally:
        mock.terminate()
        try:
            mock.wait(timeout=2)
        except subprocess.TimeoutExpired:
            mock.kill()
            mock.wait(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
