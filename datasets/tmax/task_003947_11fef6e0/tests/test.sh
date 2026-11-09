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
import os
import signal
import subprocess
import time
import uuid

import pytest
import requests

APP_DIR = "/app/vendor/simple-c-server-1.0"
SERVER = APP_DIR + "/server"
RUNNER = "/app/ci_runner.sh"


def test_makefile_fixed():
    path = "/app/vendor/simple-c-server-1.0/Makefile"
    assert os.path.isfile(path), f"Makefile missing at {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "-lthred" not in content, "Makefile still contains typo '-lthred'."
    assert "-lpthread" in content, "Makefile does not contain the correct '-lpthread' flag."


def test_nginx_config_fixed():
    path = "/app/nginx/nginx.conf"
    assert os.path.isfile(path), f"Nginx config missing at {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:9000;" in content, "Nginx config does not have the correct proxy_pass to port 9000."
    assert "proxy_pass http://127.0.0.1:9999;" not in content, "Nginx config still has the incorrect proxy_pass to port 9999."


def test_ci_runner_fixed():
    path = "/app/ci_runner.sh"
    assert os.path.isfile(path), f"CI runner script missing at {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "TZ=Etc/UTC" in content, "CI runner script does not set TZ=Etc/UTC."


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_pids(port):
    wanted = {f"socket:[{inode}]" for inode in listener_inodes(port)}
    found = set()
    if not wanted:
        return found
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") in wanted:
                        found.add(int(name))
                        break
                except OSError:
                    continue
        except OSError:
            continue
    return found


def kill_port_owners(*ports):
    pids = set()
    for port in ports:
        pids.update(listener_pids(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and any(listener_inodes(p) for p in ports):
        time.sleep(0.05)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def proc_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def proc_environ(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            return dict(item.split(b"=", 1) for item in f.read().split(b"\0") if b"=" in item)
    except OSError:
        return {}


def get_with_retry(url, timeout=5):
    session = requests.Session()
    session.trust_env = False
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            return session.get(url, timeout=1)
        except requests.RequestException as exc:
            last = exc
            time.sleep(0.05)
    pytest.fail(f"Failed to connect to {url}: {last}")


def test_build_and_runner_lifecycle():
    kill_port_owners(8080, 9000)
    try:
        os.unlink(SERVER)
    except FileNotFoundError:
        pass

    build = subprocess.run(
        ["make"], cwd=APP_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=20
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}"
    assert os.path.isfile(SERVER), "make did not create the server executable"
    assert os.access(SERVER, os.X_OK), "server produced by make is not executable"
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "server produced by make is not an ELF executable"

    # Force ci_runner.sh itself to perform the build as required.
    os.unlink(SERVER)
    started = time.time()
    runner = subprocess.Popen(
        [RUNNER], cwd="/app", stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )

    backend_pids = set()
    nginx_pids = set()
    deadline = time.time() + 15
    while time.time() < deadline:
        assert runner.poll() is None, f"ci_runner.sh exited prematurely with status {runner.returncode}"
        current_backend = listener_pids(9000)
        current_frontend = listener_pids(8080)
        if current_frontend and not backend_pids and not current_backend:
            pytest.fail("Nginx began listening before the backend was ready")
        if current_backend:
            backend_pids = current_backend
        if current_frontend:
            assert backend_pids or current_backend, "Nginx began listening before the backend"
            nginx_pids = current_frontend
            break
        time.sleep(0.05)

    assert os.path.isfile(SERVER), "ci_runner.sh did not build the server"
    assert os.path.getmtime(SERVER) >= started - 1, "ci_runner.sh did not rebuild the server"
    assert backend_pids, "backend never listened on port 9000"
    assert nginx_pids, "Nginx never listened on port 8080"

    server_real = os.path.realpath(SERVER)
    assert all(proc_exe(pid) == server_real for pid in backend_pids), \
        "port 9000 is not owned by the built C server"
    assert any(proc_environ(pid).get(b"TZ") == b"Etc/UTC" for pid in backend_pids), \
        "the running backend does not have TZ=Etc/UTC"

    nginx_exes = [proc_exe(pid) for pid in nginx_pids]
    assert nginx_exes and all(os.path.basename(exe) == "nginx" for exe in nginx_exes), \
        "port 8080 is not owned by Nginx"
    assert any("-c /app/nginx/nginx.conf" in proc_cmdline(pid) for pid in nginx_pids), \
        "the listening Nginx was not started with /app/nginx/nginx.conf"

    path = "/verify-" + uuid.uuid4().hex
    direct = get_with_retry("http://127.0.0.1:9000" + path)
    proxied = get_with_retry("http://127.0.0.1:8080" + path)
    assert direct.status_code == 200
    assert proxied.status_code == 200
    assert proxied.content == direct.content, "Nginx response does not match the backend response"
    assert proxied.headers.get("Server", "").lower().startswith("nginx"), \
        "HTTP response on port 8080 was not served by Nginx"


def test_service_is_running_and_proxying():
    url = "http://127.0.0.1:8080/status"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    assert "Status: OK" in response.text, f"Expected body to contain 'Status: OK', got {response.text!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
