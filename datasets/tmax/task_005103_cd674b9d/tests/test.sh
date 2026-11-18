#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import signal
import socket
import socketserver
import stat
import subprocess
import threading
import time
import uuid

import pytest
import requests


def get_expected_upstream_port():
    log_path = "/app/provision_events.log"
    assert os.path.isfile(log_path), f"{log_path} is missing."

    with open(log_path, "r") as f:
        lines = f.readlines()

    port = None
    for line in reversed(lines):
        match = re.search(r'\[ROUTING_UPDATE\] NEW_UPSTREAM_PORT=(\d+)', line)
        if match:
            port = match.group(1)
            break

    assert port is not None, "Could not find NEW_UPSTREAM_PORT in provision_events.log"
    return port


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def kill_matching_processes():
    own_pid = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == own_pid:
            continue
        cmdline = process_cmdline(entry)
        if "/home/user/router" in cmdline or "/home/user/start_router.sh" in cmdline:
            try:
                os.kill(int(entry), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
    time.sleep(0.4)


def kill_listener(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass

    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(entry), signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except OSError:
            pass
    time.sleep(0.5)


class DynamicBackend(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class DynamicHandler(socketserver.BaseRequestHandler):
    def handle(self):
        request = b""
        self.request.settimeout(2)
        while b"\r\n\r\n" not in request and len(request) < 65536:
            chunk = self.request.recv(4096)
            if not chunk:
                break
            request += chunk
        self.server.received.append(request)
        body = json.dumps({"nonce": self.server.nonce}).encode()
        response = (
            b"HTTP/1.1 200 OK\r\n"
            b"Content-Type: application/json\r\n"
            + f"Content-Length: {len(body)}\r\n".encode()
            + b"Connection: close\r\n\r\n"
            + body
        )
        self.request.sendall(response)


def exercise_proxy(binary, listen_port, set_listen_port=True):
    conf_path = "/home/user/upstream.conf"
    with open(conf_path, "rb") as f:
        original_conf = f.read()

    backend = DynamicBackend(("127.0.0.1", 0), DynamicHandler)
    backend.nonce = uuid.uuid4().hex
    backend.received = []
    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()

    with open(conf_path, "w") as f:
        f.write(str(backend.server_address[1]))

    env = os.environ.copy()
    if set_listen_port:
        env["LISTEN_PORT"] = str(listen_port)
    else:
        env.pop("LISTEN_PORT", None)

    proc = subprocess.Popen(
        [binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True
    )
    path = "/probe-" + uuid.uuid4().hex
    last_error = None
    try:
        for _ in range(40):
            if proc.poll() is not None:
                out, err = proc.communicate(timeout=1)
                pytest.fail(f"{binary} exited early: stdout={out!r}, stderr={err!r}")
            try:
                response = requests.get(
                    f"http://127.0.0.1:{listen_port}{path}", timeout=0.5
                )
                if response.status_code == 200 and response.json().get("nonce") == backend.nonce:
                    assert any(path.encode() in request for request in backend.received), \
                        "The dynamic upstream did not receive the proxied request"
                    return
                last_error = f"status={response.status_code}, body={response.text!r}"
            except Exception as exc:
                last_error = repr(exc)
            time.sleep(0.1)
        pytest.fail(f"Proxy did not forward the dynamic request: {last_error}")
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        backend.shutdown()
        backend.server_close()
        with open(conf_path, "wb") as f:
            f.write(original_conf)


def wait_for_original_service():
    url = "http://127.0.0.1:8080/health"
    last_exception = None
    for _ in range(30):
        try:
            response = requests.get(url, timeout=1)
            if response.status_code == 200:
                try:
                    if response.json().get("status") == "provisioned":
                        return
                except ValueError:
                    pass
            last_exception = f"Status code: {response.status_code}, Body: {response.text}"
        except requests.exceptions.RequestException as exc:
            last_exception = str(exc)
        time.sleep(0.2)
    pytest.fail(f"Failed to verify proxy service at {url}. Last error: {last_exception}")


def test_upstream_conf_content():
    expected_port = get_expected_upstream_port()
    conf_path = "/home/user/upstream.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."
    with open(conf_path, "r") as f:
        content = f.read().strip()
    assert content == expected_port, \
        f"Expected {conf_path} to contain '{expected_port}', but found '{content}'."


def test_router_binary_exists_and_executable():
    bin_path = "/home/user/router"
    assert os.path.isfile(bin_path), f"{bin_path} does not exist."
    st = os.stat(bin_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{bin_path} is not executable."
    with open(bin_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{bin_path} is not a valid ELF binary."


def test_start_router_script_exists():
    script_path = "/home/user/start_router.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."


def test_proxy_service_running_and_forwarding():
    wait_for_original_service()


def test_corrected_source_compiles_and_honors_listen_port():
    source = "/app/router.c"
    assert os.path.isfile(source), f"{source} does not exist."
    with open(source, "r") as f:
        text = f.read()
    assert re.search(r'getenv\s*\(\s*"LISTEN_PORT"\s*\)', text), \
        "router.c does not read LISTEN_PORT from the environment"

    compiled = "/tmp/router_from_submitted_source"
    result = subprocess.run(
        ["gcc", source, "-o", compiled], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"router.c does not compile: {result.stderr}"
    exercise_proxy(compiled, free_port(), set_listen_port=True)


def test_submitted_binary_is_a_dynamic_reverse_proxy():
    exercise_proxy("/home/user/router", free_port(), set_listen_port=True)


def test_submitted_binary_defaults_to_8080():
    kill_listener(8080)
    exercise_proxy("/home/user/router", 8080, set_listen_port=False)


def test_start_script_environment_logging_rotation_and_restart():
    router_path = "/home/user/router"
    saved_router = "/tmp/submitted_router_saved"
    script_path = "/home/user/start_router.sh"
    log_path = "/home/user/router.log"
    env_path = "/tmp/router_probe_env"
    pid_path = "/tmp/router_probe_pid"
    stdout_token = "PROBE_STDOUT_" + uuid.uuid4().hex
    stderr_token = "PROBE_STDERR_" + uuid.uuid4().hex

    kill_matching_processes()
    kill_listener(8080)
    for path in (log_path, env_path, pid_path, saved_router):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    os.replace(router_path, saved_router)
    try:
        probe = f'''#!/bin/bash
echo "$LISTEN_PORT" > {env_path}
echo "$$" > {pid_path}
echo "{stdout_token}"
echo "{stderr_token}" >&2
while true; do
  echo "newest-$RANDOM"
  sleep 0.2
done
'''
        with open(router_path, "w") as f:
            f.write(probe)
        os.chmod(router_path, 0o755)

        try:
            result = subprocess.run(
                ["bash", script_path], capture_output=True, text=True, timeout=3
            )
        except subprocess.TimeoutExpired:
            pytest.fail("start_router.sh did not return after starting background jobs")
        assert result.returncode == 0, \
            f"start_router.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"

        for _ in range(30):
            if os.path.exists(env_path) and os.path.exists(pid_path) and os.path.exists(log_path):
                break
            time.sleep(0.1)
        assert os.path.exists(env_path), "start_router.sh did not start /home/user/router"
        with open(env_path) as f:
            assert f.read().strip() == "8080", "start_router.sh did not set LISTEN_PORT=8080"

        for _ in range(20):
            try:
                with open(log_path, errors="replace") as f:
                    logged = f.read()
            except FileNotFoundError:
                logged = ""
            if stdout_token in logged and stderr_token in logged:
                break
            time.sleep(0.1)
        assert stdout_token in logged, "router stdout is not redirected to router.log"
        assert stderr_token in logged, "router stderr is not redirected to router.log"

        with open(log_path, "a") as f:
            f.write("ROTATION_SENTINEL_" + ("X" * 1024 * 1024) + "\n")
        before_inode = os.stat(log_path).st_ino
        before_size = os.path.getsize(log_path)
        time.sleep(12)
        assert os.path.exists(log_path), "router.log disappeared during rotation"
        after_stat = os.stat(log_path)
        assert after_stat.st_ino != before_inode or after_stat.st_size < before_size // 2, \
            "router.log was not truncated or rotated after 10 seconds"

        with open(pid_path) as f:
            probe_pid = int(f.read().strip())
        try:
            os.kill(probe_pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    finally:
        kill_matching_processes()
        try:
            os.unlink(router_path)
        except FileNotFoundError:
            pass
        if os.path.exists(saved_router):
            os.replace(saved_router, router_path)

    result = subprocess.run(
        ["bash", script_path], capture_output=True, text=True, timeout=3
    )
    assert result.returncode == 0, \
        f"start_router.sh failed when starting the real router: {result.stderr}"
    wait_for_original_service()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
