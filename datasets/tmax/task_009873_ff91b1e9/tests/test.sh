#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import errno
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading


def run(cmd, cwd=None, env=None, timeout=20):
    return subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_hook_exists_and_executable():
    """Verify the post-receive hook exists and is executable."""
    hook_path = "/home/user/targets.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Hook file does not exist at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"Hook file at {hook_path} is not executable"

    with open(hook_path, "r") as f:
        first_line = f.readline().strip()
    assert "python" in first_line.lower(), f"Hook script does not appear to be a Python script. First line: {first_line}"

    result = run([sys.executable, "-m", "py_compile", hook_path])
    assert result.returncode == 0, f"Hook is not valid Python 3: {result.stderr}"


def test_alerts_log_exists():
    """Verify the alerts.log file exists."""
    log_path = "/home/user/alerts.log"
    assert os.path.isfile(log_path), f"Log file does not exist at {log_path}"


def test_alerts_log_contents():
    """Verify the alerts.log contains the correct alert and omits the successful connection."""
    log_path = "/home/user/alerts.log"
    with open(log_path, "r") as f:
        log_contents = f.read()

    expected_alert = "ALERT: Cannot connect to 127.0.0.1:10001"
    unexpected_alert = "ALERT: Cannot connect to 127.0.0.1:10000"

    assert expected_alert in log_contents, f"Expected alert '{expected_alert}' not found in {log_path}"
    assert unexpected_alert not in log_contents, f"Unexpected alert '{unexpected_alert}' found in {log_path}"


def test_repo_has_commit():
    """Verify the bare repository has received the commit with services.json."""
    repo_path = "/home/user/targets.git"

    result = subprocess.run(
        ["git", "log", "--name-only"],
        cwd=repo_path,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, "Failed to run git log in the bare repository. Make sure a commit was pushed."
    assert "services.json" in result.stdout, "services.json was not found in the commit history of the bare repository."


def reserve_closed_port():
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return port


def start_listener():
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(8)
    listener.settimeout(0.2)
    port = listener.getsockname()[1]
    stopped = threading.Event()

    def serve():
        while not stopped.is_set():
            try:
                conn, _ = listener.accept()
                conn.close()
            except socket.timeout:
                pass
            except OSError:
                break

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    return listener, stopped, thread, port


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f)


def assert_push_succeeded(result):
    assert result.returncode == 0, (
        f"Push used to trigger post-receive failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_hook_is_triggered_and_checks_new_revision_endpoints():
    """Push a derived revision and verify every JSON endpoint is actually checked."""
    listener, stopped, thread, open_port = start_listener()
    closed_port = reserve_closed_port()
    while closed_port == open_port:
        closed_port = reserve_closed_port()

    try:
        with tempfile.TemporaryDirectory(prefix="hook-verifier-") as work:
            result = run(["git", "clone", "/home/user/targets.git", work])
            assert result.returncode == 0, result.stderr
            assert run(["git", "config", "user.email", "verifier@example.com"], cwd=work).returncode == 0
            assert run(["git", "config", "user.name", "Verifier"], cwd=work).returncode == 0

            result = run(["git", "checkout", "--orphan", "verifier-controlled"], cwd=work)
            assert result.returncode == 0, result.stderr
            result = run(["git", "rm", "-rf", "--ignore-unmatch", "."], cwd=work)
            assert result.returncode == 0, result.stderr

            write_json(
                os.path.join(work, "services.json"),
                {"endpoints": [{"host": "127.0.0.1", "port": open_port}]},
            )
            write_json(
                os.path.join(work, "nested", "additional.json"),
                {"endpoints": [{"host": "127.0.0.1", "port": closed_port}]},
            )
            with open(os.path.join(work, "ignored.txt"), "w") as f:
                f.write("not JSON")

            assert run(["git", "add", "-A"], cwd=work).returncode == 0
            result = run(["git", "commit", "-m", "verifier controlled endpoints"], cwd=work)
            assert result.returncode == 0, result.stderr

            open("/home/user/alerts.log", "w").close()
            result = run(["git", "push", "--force", "origin", "HEAD:master"], cwd=work)
            assert_push_succeeded(result)

            with open("/home/user/alerts.log") as f:
                lines = f.read().splitlines()
            assert lines == [f"ALERT: Cannot connect to 127.0.0.1:{closed_port}"], (
                "The hook must inspect all .json files at newrev, log the failed endpoint exactly once, "
                f"and omit the reachable endpoint. Log lines were: {lines!r}"
            )

            _exercise_timeout_with_instrumented_socket(work, open_port, closed_port)
    finally:
        stopped.set()
        listener.close()
        thread.join(timeout=1)


def _exercise_timeout_with_instrumented_socket(work, success_port, failure_port):
    """Trigger a second push while instrumenting socket calls to verify the 1-second timeout."""
    write_json(
        os.path.join(work, "services.json"),
        {"endpoints": [{"host": "127.0.0.1", "port": success_port}]},
    )
    write_json(
        os.path.join(work, "nested", "additional.json"),
        {"endpoints": [{"host": "127.0.0.1", "port": failure_port}]},
    )
    with open(os.path.join(work, "revision-marker.txt"), "w") as f:
        f.write("second revision")
    assert run(["git", "add", "-A"], cwd=work).returncode == 0
    result = run(["git", "commit", "-m", "exercise timeout handling"], cwd=work)
    assert result.returncode == 0, result.stderr

    shim_dir = tempfile.mkdtemp(prefix="socket-instrumentation-")
    calls_path = os.path.join(shim_dir, "calls.jsonl")
    sitecustomize = r'''
import errno
import json
import os
import socket as _socket

_calls = os.environ["HOOK_SOCKET_CALLS"]
_failure_port = int(os.environ["HOOK_FAILURE_PORT"])
_default_timeout = None


def _record(address, timeout):
    with open(_calls, "a") as f:
        f.write(json.dumps({"host": address[0], "port": int(address[1]), "timeout": timeout}) + "\\n")


class InstrumentedSocket:
    def __init__(self, *args, **kwargs):
        self._timeout = _default_timeout

    def settimeout(self, value):
        self._timeout = value

    def gettimeout(self):
        return self._timeout

    def connect(self, address):
        _record(address, self._timeout)
        if int(address[1]) == _failure_port:
            raise _socket.timeout("instrumented timeout")
        return None

    def connect_ex(self, address):
        _record(address, self._timeout)
        return errno.ETIMEDOUT if int(address[1]) == _failure_port else 0

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False


def instrumented_create_connection(address, timeout=None, source_address=None, all_errors=False):
    effective = _default_timeout if timeout is None else timeout
    _record(address, effective)
    if int(address[1]) == _failure_port:
        raise _socket.timeout("instrumented timeout")
    return InstrumentedSocket()


def instrumented_setdefaulttimeout(value):
    global _default_timeout
    _default_timeout = value


_socket.socket = InstrumentedSocket
_socket.create_connection = instrumented_create_connection
_socket.setdefaulttimeout = instrumented_setdefaulttimeout
'''
    with open(os.path.join(shim_dir, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)

    env = os.environ.copy()
    env["PYTHONPATH"] = shim_dir
    env["HOOK_SOCKET_CALLS"] = calls_path
    env["HOOK_FAILURE_PORT"] = str(failure_port)
    open("/home/user/alerts.log", "w").close()

    result = run(["git", "push", "--force", "origin", "HEAD:master"], cwd=work, env=env)
    assert_push_succeeded(result)
    assert os.path.isfile(calls_path), "The triggered hook did not make instrumented socket connections"

    with open(calls_path) as f:
        calls = [json.loads(line) for line in f if line.strip()]

    for port in (success_port, failure_port):
        matching = [call for call in calls if call["host"] == "127.0.0.1" and call["port"] == port]
        assert matching, f"No TCP connection was attempted for 127.0.0.1:{port}; calls were {calls!r}"
        assert any(
            call["timeout"] is not None and abs(float(call["timeout"]) - 1.0) < 0.01
            for call in matching
        ), f"Connection to 127.0.0.1:{port} was not attempted with a 1-second timeout: {matching!r}"

    with open("/home/user/alerts.log") as f:
        lines = f.read().splitlines()
    assert lines == [f"ALERT: Cannot connect to 127.0.0.1:{failure_port}"], (
        "Instrumented successful and timed-out connections were not logged correctly: " + repr(lines)
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
