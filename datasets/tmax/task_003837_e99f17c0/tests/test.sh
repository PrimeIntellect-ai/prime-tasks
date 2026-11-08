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
import re
import signal
import socket
import subprocess
import time

import pytest
import requests

DEPLOY = "/home/user/deploy.sh"
SERVER = "/home/user/app/target/release/server"
REAL_SERVER = "/home/user/app/target/release/.verifier-real-server"
NGINX = "/usr/sbin/nginx"
REAL_NGINX = "/usr/sbin/.verifier-real-nginx"
NGINX_CONF = "/home/user/nginx/nginx.conf"
NGINX_PID = "/home/user/nginx/nginx.pid"
RELOAD_LOG = "/tmp/verifier-nginx-reloads.log"
OLD_PID_FILE = "/tmp/verifier-old-server-pids"


def wait_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f"Port {port} did not become available")


def port_pids(port):
    result = subprocess.run(
        ["fuser", "-n", "tcp", str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return {int(value) for value in result.stdout.split() if value.isdigit()}


def terminate_port(port):
    pids = port_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and any(os.path.exists(f"/proc/{pid}") for pid in pids):
        time.sleep(0.05)
    for pid in pids:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def wait_gone(pids, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if all(not os.path.exists(f"/proc/{pid}") for pid in pids):
            return
        time.sleep(0.05)
    raise AssertionError(f"Existing server process(es) were not terminated: {sorted(pids)}")


def assert_server_owns_port():
    pids = port_pids(8081)
    assert pids, "No process is listening on the required Rust service port 8081"
    matching = []
    for pid in pids:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", SERVER):
                matching.append(pid)
        except (FileNotFoundError, PermissionError):
            pass
    assert matching, f"Port 8081 is not owned by the supplied Rust server binary; listener PIDs: {sorted(pids)}"
    return set(matching)


def read_nginx_pid():
    with open(NGINX_PID) as f:
        return int(f.read().strip())


def run_deploy():
    env = os.environ.copy()
    env.pop("PORT", None)
    result = subprocess.run(
        [DEPLOY], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=15,
    )
    assert result.returncode == 0, f"deploy.sh failed with exit code {result.returncode}:\n{result.stdout}"


@pytest.fixture(scope="session", autouse=True)
def exercise_deployment_script():
    assert os.path.isfile(SERVER), f"Rust server binary missing at {SERVER}"
    assert os.access(SERVER, os.X_OK), "Rust server binary is not executable"
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The supplied Rust server binary was replaced with a non-ELF artifact"

    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    terminate_port(8080)
    terminate_port(8081)
    for path in (NGINX_PID, RELOAD_LOG, OLD_PID_FILE):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    old_env = os.environ.copy()
    old_env["PORT"] = "8081"
    old_server = subprocess.Popen(
        [SERVER], cwd="/home/user/app", env=old_env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    wait_port(8081)
    old_pids = port_pids(8081)
    assert old_server.pid in old_pids
    with open(OLD_PID_FILE, "w") as f:
        f.write(" ".join(map(str, sorted(old_pids))))

    subprocess.run([NGINX, "-c", NGINX_CONF], check=True)
    wait_port(8080)
    master_pid = read_nginx_pid()

    server_moved = False
    nginx_moved = False
    try:
        os.rename(SERVER, REAL_SERVER)
        server_moved = True
        with open(SERVER, "w") as f:
            f.write("#!/bin/bash\nsleep 1\nexec /home/user/app/target/release/.verifier-real-server \"$@\"\n")
        os.chmod(SERVER, 0o755)

        os.rename(NGINX, REAL_NGINX)
        nginx_moved = True
        with open(NGINX, "w") as f:
            f.write("""#!/bin/bash
state=OTHER
if [ \"$#\" -eq 4 ] && [ \"$1\" = \"-c\" ] && [ \"$2\" = \"/home/user/nginx/nginx.conf\" ] && [ \"$3\" = \"-s\" ] && [ \"$4\" = \"reload\" ]; then
    state=READY
    for pid in $(cat /tmp/verifier-old-server-pids 2>/dev/null); do
        if kill -0 \"$pid\" 2>/dev/null; then state=NOT_READY; fi
    done
    python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",8081),.3); s.close()' >/dev/null 2>&1 || state=NOT_READY
    echo \"EXACT $state\" >> /tmp/verifier-nginx-reloads.log
else
    echo \"OTHER $*\" >> /tmp/verifier-nginx-reloads.log
fi
exec /usr/sbin/.verifier-real-nginx \"$@\"
""")
        os.chmod(NGINX, 0o755)

        run_deploy()
        wait_gone(old_pids)
        assert read_nginx_pid() == master_pid, "Nginx master was restarted instead of gracefully reloaded"

        os.unlink(SERVER)
        os.rename(REAL_SERVER, SERVER)
        server_moved = False
        first_pids = assert_server_owns_port()
        with open(OLD_PID_FILE, "w") as f:
            f.write(" ".join(map(str, sorted(first_pids))))

        run_deploy()
        wait_gone(first_pids)
        second_pids = assert_server_owns_port()
        assert second_pids.isdisjoint(first_pids), "Second deployment did not replace the existing Rust server process"
        assert read_nginx_pid() == master_pid, "Nginx master was restarted instead of gracefully reloaded"

        with open(RELOAD_LOG) as f:
            reload_lines = [line.strip() for line in f if line.startswith("EXACT ")]
        assert reload_lines == ["EXACT READY", "EXACT READY"], (
            "Each deployment must invoke `nginx -c /home/user/nginx/nginx.conf -s reload` "
            "only after the newly started service is available"
        )
    finally:
        if server_moved:
            try:
                os.unlink(SERVER)
            except FileNotFoundError:
                pass
            if os.path.exists(REAL_SERVER):
                os.rename(REAL_SERVER, SERVER)
        if nginx_moved:
            try:
                os.unlink(NGINX)
            except FileNotFoundError:
                pass
            if os.path.exists(REAL_NGINX):
                os.rename(REAL_NGINX, NGINX)


def test_deploy_script_exists_and_executable():
    path = "/home/user/deploy.sh"
    assert os.path.isfile(path), f"Deployment script missing at {path}"
    assert os.access(path, os.X_OK), f"Deployment script at {path} is not executable (missing +x)"


def test_deploy_script_contents():
    path = "/home/user/deploy.sh"
    with open(path, 'r') as f:
        content = f.read()

    assert "server" in content, "Deployment script does not seem to reference the Rust server binary"
    assert "nginx" in content, "Deployment script does not seem to reference nginx"
    assert "reload" in content, "Deployment script does not seem to perform an nginx reload"


def test_health_endpoint():
    url = "http://127.0.0.1:8080/health"
    try:
        response = requests.get(url, timeout=5)
        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

        data = response.json()
        assert data == {"status": "ok"}, f"Expected JSON {{'status': 'ok'}}, got {data}"
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to {url} or request failed: {e}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
