#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import stat
import subprocess
import time
import urllib.error
import urllib.request
import uuid

EXP_PATH = "/home/user/auto_deploy.exp"
DEPLOY_PATH = "/home/user/deploy.sh"
APP_PATH = "/home/user/backend/app.py"
PID_PATH = "/home/user/backend/app.pid"
CONFIG_PATH = "/home/user/nginx/nginx.conf"
LOG_PATH = "/home/user/resolution.log"

EXPECTED_DEPLOY = '''#!/bin/bash
read -p "Environment (dev/prod): " env
read -p "Confirm start? [y/N]: " conf

if [ "$env" == "prod" ] && [ "$conf" == "y" ]; then
    echo "Starting backend..."
    python3 /home/user/backend/app.py &
    echo $! > /home/user/backend/app.pid
    sleep 1
    echo "Backend started."
else
    echo "Deployment aborted."
    exit 1
fi
'''

EXPECTED_APP = '''import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Hello from Production backend!")

if __name__ == "__main__":
    # App purposefully runs on 9001 instead of 9000
    server = HTTPServer(("127.0.0.1", 9001), Handler)
    server.serve_forever()
'''


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return []


def backend_pids():
    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        args = cmdline(int(name))
        if APP_PATH in args:
            result.append(int(name))
    return result


def stop_backends():
    pids = backend_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and backend_pids():
        time.sleep(0.1)
    for pid in backend_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and backend_pids():
        time.sleep(0.05)
    assert not backend_pids(), "Could not stop the existing backend before testing deployment."


def run_expect(timeout=12):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "/usr/bin/expect", "-f", EXP_PATH],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    ).returncode


def wait_for_backend(timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if backend_pids():
            try:
                status, _ = http_get("http://127.0.0.1:9001/health-check", timeout=0.5)
                if status == 200:
                    return
            except OSError:
                pass
        time.sleep(0.1)
    raise AssertionError("The Python backend (app.py) was not started on port 9001.")


def http_get(url, timeout=2):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def test_final_deployment_state():
    # Preserve the original artifact and source assertions, and ensure prohibited
    # files were not changed to make deployment artificially succeed.
    assert os.path.isfile(EXP_PATH), f"The expect script {EXP_PATH} is missing."
    assert stat.S_ISREG(os.stat(EXP_PATH).st_mode), f"{EXP_PATH} is not a regular file."
    with open(DEPLOY_PATH) as f:
        assert f.read() == EXPECTED_DEPLOY, "deploy.sh was modified."
    with open(APP_PATH) as f:
        assert f.read() == EXPECTED_APP, "The backend Python code was modified."

    # Exercise the expect program against the real prompts using a temporary
    # deployment fixture. A random marker is produced only after prod and y are
    # received as separate answers.
    token = uuid.uuid4().hex
    marker = f"/tmp/expect-interaction-{token}"
    with open(DEPLOY_PATH, "rb") as f:
        original_deploy = f.read()
    original_mode = stat.S_IMODE(os.stat(DEPLOY_PATH).st_mode)
    fixture = f'''#!/bin/bash
printf 'Environment (dev/prod): ' >&2
IFS= read -r env
printf 'Confirm start? [y/N]: ' >&2
IFS= read -r conf
if [ "$env" = "prod" ] && [ "$conf" = "y" ]; then
    printf '%s' '{token}' > '{marker}'
    echo 'Backend started.'
    exit 0
fi
exit 1
'''
    try:
        with open(DEPLOY_PATH, "w") as f:
            f.write(fixture)
        os.chmod(DEPLOY_PATH, 0o755)
        rc = run_expect()
        assert rc == 0, "The expect script failed while responding to the deployment prompts."
        assert os.path.isfile(marker), "The expect script did not provide prod and y to deploy.sh."
        with open(marker) as f:
            assert f.read() == token, "The deployment interaction marker was invalid."
    finally:
        with open(DEPLOY_PATH, "wb") as f:
            f.write(original_deploy)
        os.chmod(DEPLOY_PATH, original_mode)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass

    # Run the submitted expect script against the actual deployment script from
    # a clean backend state and require deploy.sh's fresh PID file to identify it.
    stop_backends()
    try:
        os.unlink(PID_PATH)
    except FileNotFoundError:
        pass
    started_at = time.time()
    assert run_expect() == 0, "The expect script did not successfully run the real deploy.sh."
    wait_for_backend()
    assert os.path.isfile(PID_PATH), "deploy.sh did not create the backend PID file."
    assert os.path.getmtime(PID_PATH) >= started_at - 1, "The backend PID file was not freshly created."
    with open(PID_PATH) as f:
        deployed_pid = int(f.read().strip())
    assert deployed_pid in backend_pids(), "deploy.sh's PID does not identify the running app.py backend."

    # Retain the original configuration assertion, then require it to be an
    # active proxy_pass directive in a syntactically valid Nginx configuration.
    assert os.path.isfile(CONFIG_PATH), f"Nginx config file {CONFIG_PATH} is missing."
    with open(CONFIG_PATH) as f:
        config = f.read()
    assert "127.0.0.1:9001" in config or "localhost:9001" in config, \
        f"Nginx config {CONFIG_PATH} does not correctly route to the backend on port 9001."
    uncommented = re.sub(r"#.*", "", config)
    assert re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):9001(?:/)?\s*;", uncommented), \
        "The corrected backend address is not used by an active proxy_pass directive."
    syntax = subprocess.run(
        ["nginx", "-t", "-p", "/home/user/nginx", "-c", CONFIG_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert syntax.returncode == 0, f"The Nginx configuration is invalid: {syntax.stdout}"

    # Verify that the configured Nginx master is actually running.
    nginx_pid_path = "/home/user/nginx/nginx.pid"
    assert os.path.isfile(nginx_pid_path), "The user-space Nginx PID file is missing."
    with open(nginx_pid_path) as f:
        nginx_pid = int(f.read().strip())
    nginx_args = cmdline(nginx_pid)
    assert nginx_args, "The Nginx process recorded in nginx.pid is not running."
    nginx_exe = os.path.basename(os.readlink(f"/proc/{nginx_pid}/exe"))
    assert nginx_exe.startswith("nginx"), "nginx.pid does not identify an Nginx process."

    # Derive the expected response from the live backend and compare it with a
    # request through port 8080 on a unique path.
    request_path = "/verifier-" + uuid.uuid4().hex
    direct_status, direct_body = http_get("http://127.0.0.1:9001" + request_path)
    proxy_status, proxy_body = http_get("http://127.0.0.1:8080" + request_path)
    assert direct_status == 200, f"The backend returned HTTP {direct_status}."
    assert proxy_status == direct_status, f"Nginx returned HTTP {proxy_status}, backend returned {direct_status}."
    assert proxy_body == direct_body, "The response through Nginx does not match the live backend response."

    # Closing the backend must break the same proxy request; this prevents a
    # fabricated static server on 8080 from satisfying the response comparison.
    stop_backends()
    down_status, down_body = http_get("http://127.0.0.1:8080" + request_path)
    assert down_status != 200 or down_body != direct_body, \
        "Port 8080 still served the backend response after the backend was stopped."

    # Restore the required final state by running the submitted deployment
    # automation again, then make one final end-to-end request.
    assert run_expect() == 0, "The expect script could not restart the backend."
    wait_for_backend()
    final_direct_status, final_direct_body = http_get("http://127.0.0.1:9001" + request_path)
    final_proxy_status, final_proxy_body = http_get("http://127.0.0.1:8080" + request_path)
    assert final_direct_status == final_proxy_status == 200
    assert final_proxy_body == final_direct_body

    # Keep the original exact resolution-log assertion and also tie it to the
    # response currently returned through the proxy.
    assert os.path.isfile(LOG_PATH), f"The resolution log file {LOG_PATH} is missing."
    with open(LOG_PATH, "rb") as f:
        logged_raw = f.read()
    content = logged_raw.decode().strip()
    expected = "Hello from Production backend!"
    assert content == expected, f"Content of {LOG_PATH} does not match expected output. Got: {content}"
    assert logged_raw == final_proxy_body, \
        "resolution.log is not the raw response body currently served through Nginx."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
