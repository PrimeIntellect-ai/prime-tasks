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
import stat
import subprocess
import time

import pytest
import requests

NGINX_CONF = "/app/nginx/nginx.conf"
APP_PY = "/app/api/app.py"
EXPECTED_UP = {"status": "ok", "env": "development", "redis_ping": True}
EXPECTED_DOWN = {"status": "ok", "env": "development", "redis_ping": False}


def test_files_moved_and_renamed():
    assert os.path.isfile(NGINX_CONF), f"File {NGINX_CONF} is missing. Did you move and rename it correctly?"
    assert os.path.isfile(APP_PY), f"File {APP_PY} is missing. Did you move and rename it correctly?"
    assert stat.S_ISREG(os.stat(NGINX_CONF, follow_symlinks=False).st_mode), f"{NGINX_CONF} must be a regular file"
    assert stat.S_ISREG(os.stat(APP_PY, follow_symlinks=False).st_mode), f"{APP_PY} must be a regular file"

    leftovers = []
    for root, _, files in os.walk("/app/messy_files"):
        for name in files:
            if name.endswith(".prod.bak") or name.endswith(".py.bak"):
                leftovers.append(os.path.join(root, name))
    assert not leftovers, f"Backup-suffixed files were not bulk-renamed: {leftovers}"


def test_nginx_conf_content():
    if not os.path.isfile(NGINX_CONF):
        pytest.fail(f"Cannot test content because {NGINX_CONF} is missing.")

    with open(NGINX_CONF, "r") as f:
        content = f.read()

    assert "127.0.0.1:5000" in content, "The upstream address in nginx.conf was not updated to 127.0.0.1:5000."
    assert "backend.example.com:80" not in content, "The old upstream address backend.example.com:80 is still in nginx.conf."

    checked = subprocess.run(
        ["/usr/sbin/nginx", "-t", "-c", NGINX_CONF],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert checked.returncode == 0, f"nginx.conf is not a valid Nginx configuration:\n{checked.stdout}"

    dumped = subprocess.run(
        ["/usr/sbin/nginx", "-T", "-c", NGINX_CONF],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert dumped.returncode == 0, f"Could not load nginx.conf:\n{dumped.stdout}"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:5000\s*;", dumped.stdout), \
        "The active Nginx configuration does not proxy to the Flask service"


def test_app_py_content():
    if not os.path.isfile(APP_PY):
        pytest.fail(f"Cannot test content because {APP_PY} is missing.")

    with open(APP_PY, "r") as f:
        content = f.read()

    assert 'DB_HOST = "127.0.0.1"' in content, "The DB_HOST in app.py was not updated to 127.0.0.1."
    assert "redis.prod.internal" not in content, "The old DB_HOST redis.prod.internal is still in app.py."
    assert 'ENV = "development"' in content, "The ENV in app.py was not updated to development."
    assert "production" not in content, "The old ENV production is still in app.py."

    compiled = subprocess.run(
        ["python3", "-m", "py_compile", APP_PY],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert compiled.returncode == 0, f"app.py is not valid Python:\n{compiled.stdout}"


def wait_for_json(url, process, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        assert process.poll() is None, "Required service exited during startup"
        try:
            response = requests.get(url, timeout=1)
            if response.status_code == 200:
                return response
            last_error = f"HTTP {response.status_code}: {response.text}"
        except requests.RequestException as exc:
            last_error = str(exc)
        time.sleep(0.2)
    pytest.fail(f"Service did not become ready at {url}: {last_error}")


def start_redis():
    proc = subprocess.Popen(
        ["redis-server", "--bind", "127.0.0.1", "--port", "6379", "--save", "", "--appendonly", "no", "--daemonize", "no"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        assert proc.poll() is None, "Redis failed to start on 127.0.0.1:6379"
        ping = subprocess.run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "ping"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        if ping.returncode == 0 and ping.stdout.strip() == "PONG":
            return proc
        time.sleep(0.1)
    proc.terminate()
    pytest.fail("Redis did not become ready")


def test_health_endpoint():
    # Remove pre-existing instances so the test must execute the submitted artifacts.
    subprocess.run(["pkill", "-TERM", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-TERM", "-f", "^python3 /app/api/app.py$"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-TERM", "-x", "redis-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)

    redis_proc = start_redis()
    app_proc = subprocess.Popen(["python3", APP_PY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for_json("http://127.0.0.1:5000/health", app_proc)

    nginx_proc = subprocess.Popen(
        ["/usr/sbin/nginx", "-c", NGINX_CONF, "-g", "daemon off; pid /tmp/verifier-nginx.pid;"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    url = "http://127.0.0.1:8080/health"
    response = wait_for_json(url, nginx_proc)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data == EXPECTED_UP, f"Expected JSON response {EXPECTED_UP}, but got {data}"
    assert response.headers.get("Server", "").lower().startswith("nginx"), "Port 8080 is not being served by Nginx"
    assert app_proc.poll() is None, "The submitted Flask application is not running"
    assert nginx_proc.poll() is None, "Nginx is not running with the submitted configuration"

    # Redis availability is varied after startup so a hardcoded health response cannot pass.
    redis_proc.terminate()
    redis_proc.wait(timeout=5)
    time.sleep(0.3)
    down_response = requests.get(url, timeout=3)
    assert down_response.status_code == 200
    assert down_response.json() == EXPECTED_DOWN, \
        "The Flask health endpoint did not detect that Redis became unavailable"

    redis_proc = start_redis()
    restored_response = requests.get(url, timeout=3)
    assert restored_response.status_code == 200
    assert restored_response.json() == EXPECTED_UP, \
        "The Flask health endpoint did not detect that Redis was restored"

    direct_response = requests.get("http://127.0.0.1:5000/health", timeout=3)
    assert direct_response.status_code == 200
    assert direct_response.json() == EXPECTED_UP, "The submitted Flask application does not provide the required health response"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
