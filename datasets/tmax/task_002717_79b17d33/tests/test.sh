#!/bin/bash
mkdir -p /logs/verifier

# Stop services left behind by the required supervisor run so they cannot
# interfere with isolated behavioral checks.
pkill -f '^python3 /home/user/supervisor.py$' 2>/dev/null || true
pkill -f '^python3 /home/user/data_service.py$' 2>/dev/null || true
pkill -f '^python3 /home/user/worker.py$' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import textwrap
import time


def test_status_log_exists_and_correct():
    log_path = "/home/user/status.log"
    assert os.path.isfile(log_path), f"The file {log_path} does not exist. Did the supervisor run successfully and start the worker?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert "STATUS: MIGRATION_SUCCESS" in content, f"The file {log_path} does not contain the expected success message. Content found: {content}"


def test_supervisor_modifications():
    supervisor_path = "/home/user/supervisor.py"
    assert os.path.isfile(supervisor_path), f"Missing file: {supervisor_path}"

    with open(supervisor_path, "r") as f:
        content = f.read()

    # Preserve the original verifier's assertions.
    assert "socket" in content, "The supervisor.py script does not seem to import or use 'socket' for readiness checking."
    assert "env" in content or "environ" in content, "The supervisor.py script does not seem to handle environment variables (missing 'env' or 'environ')."


def _free_port():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def _run_behavior_case(delay):
    services_path = "/home/user/services.json"
    with open(services_path, "rb") as f:
        original_services = f.read()

    with tempfile.TemporaryDirectory(prefix="supervisor_test_") as td:
        server_path = os.path.join(td, "delayed_service.py")
        worker_path = os.path.join(td, "dependent_worker.py")
        ready_path = os.path.join(td, "ready.time")
        worker_started_path = os.path.join(td, "worker.time")
        result_path = os.path.join(td, "result.txt")
        port = _free_port()

        with open(server_path, "w") as f:
            f.write(textwrap.dedent("""
                import os
                import socket
                import sys
                import time

                port = int(sys.argv[1])
                delay = float(sys.argv[2])
                ready_file = sys.argv[3]
                time.sleep(delay)
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock.bind(('127.0.0.1', port))
                sock.listen(8)
                sock.settimeout(0.1)
                with open(ready_file, 'w') as out:
                    out.write(str(time.monotonic()))
                last_connection = None
                while last_connection is None or time.monotonic() - last_connection < 1.2:
                    try:
                        conn, _ = sock.accept()
                    except socket.timeout:
                        continue
                    last_connection = time.monotonic()
                    try:
                        conn.sendall(b'READY')
                    except OSError:
                        pass
                    conn.close()
                sock.close()
            """))

        with open(worker_path, "w") as f:
            f.write(textwrap.dedent("""
                import os
                import socket
                import sys
                import time

                port = int(sys.argv[1])
                started_file = sys.argv[2]
                result_file = sys.argv[3]
                with open(started_file, 'w') as out:
                    out.write(str(time.monotonic()))
                if os.environ.get('CONFIG_ONLY') != 'injected':
                    sys.exit(20)
                if os.environ.get('TEST_INHERITED') != 'keep':
                    sys.exit(21)
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(1.0)
                try:
                    sock.connect(('127.0.0.1', port))
                    data = sock.recv(32)
                except OSError:
                    sys.exit(22)
                finally:
                    sock.close()
                if data != b'READY':
                    sys.exit(23)
                with open(result_file, 'w') as out:
                    out.write('ok')
            """))

        # Put the dependent service first to ensure the supervisor actually
        # resolves depends_on rather than relying on JSON insertion order.
        config = {
            "dependent": {
                "cmd": f"{sys.executable} {worker_path} {port} {worker_started_path} {result_path}",
                "depends_on": "dependency",
                "env": {"CONFIG_ONLY": "injected"},
            },
            "dependency": {
                "cmd": f"{sys.executable} {server_path} {port} {delay} {ready_path}",
                "port": port,
            },
        }

        started = time.monotonic()
        try:
            with open(services_path, "w") as f:
                json.dump(config, f)

            env = os.environ.copy()
            env["TEST_INHERITED"] = "keep"
            proc = subprocess.Popen(
                [sys.executable, "/home/user/supervisor.py"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                start_new_session=True,
            )
            try:
                stdout, stderr = proc.communicate(timeout=12)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                stdout, stderr = proc.communicate()
                raise AssertionError(f"Supervisor did not complete behavioral test. stdout={stdout!r}, stderr={stderr!r}")
        finally:
            with open(services_path, "wb") as f:
                f.write(original_services)

        assert proc.returncode == 0, f"Supervisor exited with {proc.returncode}. stdout={stdout!r}, stderr={stderr!r}"
        assert os.path.isfile(ready_path), "The dependency service was not started."
        assert os.path.isfile(worker_started_path), "The dependent service was not started."
        assert os.path.isfile(result_path), "The dependent service failed; dependency readiness or environment handling is incorrect."
        with open(result_path) as f:
            assert f.read() == "ok"

        with open(ready_path) as f:
            ready_time = float(f.read())
        with open(worker_started_path) as f:
            worker_time = float(f.read())

        assert worker_time >= ready_time - 0.05, "The dependent service was launched before its dependency became ready."
        assert worker_time - ready_time < 1.5, "The dependent service was not launched promptly after readiness was detected."
        if delay == 0:
            assert worker_time - started < 2.0, "An immediately ready dependency was not detected by active polling."


def test_dependency_readiness_and_environment_behavior():
    # The immediate and delayed cases together reject both simultaneous startup
    # and implementations that merely use a fixed conservative sleep.
    _run_behavior_case(0)
    _run_behavior_case(2.4)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
