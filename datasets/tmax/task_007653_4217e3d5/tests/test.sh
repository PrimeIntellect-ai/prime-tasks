#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SPY_EOF' > /tmp/proxy_spy.py
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

mode, log_path = sys.argv[1], sys.argv[2]
count = 0

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global count
        count += 1
        with open(log_path, "a") as f:
            f.write(self.path + "\n")
            f.flush()
        body = b"41" if mode == "bad" and count == 1 else b"42"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
SPY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import gc
import os
import secrets
import socket
import subprocess
import sys
import time
import urllib.request

APP = "/home/user/app"
NGINX_CONF = os.path.join(APP, "nginx.conf")


def fetch(value):
    url = f"http://127.0.0.1:8080/compute?val={value}"
    with urllib.request.urlopen(url, timeout=5) as response:
        return response.getcode(), response.read().decode("utf-8").strip()


def port_open(port=8080):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.2):
            return True
    except OSError:
        return False


def wait_for_port(expected_open, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if port_open() == expected_open:
            return True
        time.sleep(0.1)
    return False


def test_libcalc_shared_object():
    """Verify libcalc.so is built as a valid shared object."""
    so_path = os.path.join(APP, "libcalc.so")
    assert os.path.isfile(so_path), f"{so_path} does not exist. Did you run make?"

    result = subprocess.run(["file", so_path], capture_output=True, text=True)
    assert "shared object" in result.stdout, f"{so_path} is not a valid shared object. Check your Makefile."

    lib = ctypes.CDLL(so_path)
    lib.calculate.argtypes = [ctypes.c_int]
    lib.calculate.restype = ctypes.c_int
    for value in (0, 1, 10, 21, secrets.randbelow(10000) + 100):
        assert lib.calculate(value) == value * 2


def test_memory_leak_fixed():
    """Verify the source leak is removed and repeated requests do not retain ~1MB each."""
    api_path = os.path.join(APP, "api.py")
    assert os.path.isfile(api_path), f"{api_path} does not exist."

    with open(api_path, "r") as f:
        content = f.read()
    assert "history.append" not in content, "Memory leak (history.append) is still present in api.py."

    probe = r'''
import gc
import importlib.util
import os

os.chdir("/home/user/app")
spec = importlib.util.spec_from_file_location("submitted_api", "/home/user/app/api.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
client = module.app.test_client()
for _ in range(5):
    response = client.get("/compute?val=21")
    assert response.status_code == 200 and response.get_data(as_text=True).strip() == "42"
gc.collect()
page = os.sysconf("SC_PAGE_SIZE")
def rss():
    with open("/proc/self/statm") as f:
        return int(f.read().split()[1]) * page
before = rss()
for _ in range(30):
    response = client.get("/compute?val=21")
    assert response.status_code == 200 and response.get_data(as_text=True).strip() == "42"
gc.collect()
after = rss()
print(after - before)
'''
    result = subprocess.run([sys.executable, "-c", probe], cwd=APP, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"API memory probe failed: {result.stdout}\n{result.stderr}"
    growth = int(result.stdout.strip().splitlines()[-1])
    assert growth < 12 * 1024 * 1024, f"API retained {growth} bytes across 30 requests; the per-request leak remains"


def test_nginx_proxy_and_api_functional():
    """Verify Nginx reverse proxy works for the original and unpredictable inputs."""
    status, body = fetch(10)
    assert status == 200, f"Expected HTTP 200, got {status}"
    assert body == "20", f"Expected response body '20', got '{body}'"

    values = [21] + [secrets.randbelow(100000) + 1 for _ in range(7)]
    for value in values:
        status, body = fetch(value)
        assert status == 200, f"Expected HTTP 200 for val={value}, got {status}"
        assert body == str(value * 2), f"Expected {value * 2} for val={value}, got '{body}'"


def test_test_script_exists():
    """Verify the test script was created."""
    test_path = os.path.join(APP, "test.py")
    assert os.path.isfile(test_path), f"{test_path} was not created."


def test_execute_required_test_script():
    """Run test.py against an observed proxy and verify its requests and assertions."""
    test_path = os.path.join(APP, "test.py")
    assert os.path.isfile(test_path), f"{test_path} was not created."
    assert os.path.isfile(NGINX_CONF), f"{NGINX_CONF} was not created."

    config_check = subprocess.run(["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True)
    assert config_check.returncode == 0, f"Invalid nginx configuration: {config_check.stdout}\n{config_check.stderr}"

    subprocess.run(["nginx", "-c", NGINX_CONF, "-s", "quit"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not wait_for_port(False, 4):
        subprocess.run(["pkill", "-TERM", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert wait_for_port(False, 4), "Port 8080 was not released by nginx configured with nginx.conf"

    spy = None
    try:
        success_log = os.path.join(APP, "success.log")
        request_log = "/tmp/test_script_requests.log"

        if os.path.exists(success_log):
            os.remove(success_log)
        open(request_log, "w").close()
        spy = subprocess.Popen([sys.executable, "/tmp/proxy_spy.py", "bad", request_log])
        assert wait_for_port(True, 3), "Could not start verifier proxy"
        bad = subprocess.run([sys.executable, test_path], cwd=APP, capture_output=True, text=True, timeout=20)
        spy.terminate()
        spy.wait(timeout=3)
        spy = None
        assert bad.returncode != 0, "test.py did not fail when one response was not 42"
        assert not os.path.exists(success_log), "test.py wrote success.log despite receiving an incorrect response"

        open(request_log, "w").close()
        spy = subprocess.Popen([sys.executable, "/tmp/proxy_spy.py", "good", request_log])
        assert wait_for_port(True, 3), "Could not restart verifier proxy"
        good = subprocess.run([sys.executable, test_path], cwd=APP, capture_output=True, text=True, timeout=20)
        spy.terminate()
        spy.wait(timeout=3)
        spy = None
        assert good.returncode == 0, f"test.py failed: {good.stdout}\n{good.stderr}"

        with open(request_log) as f:
            paths = [line.strip() for line in f if line.strip()]
        assert len(paths) == 10, f"test.py made {len(paths)} requests instead of 10"
        assert all(path == "/compute?val=21" for path in paths), f"test.py used unexpected request paths: {paths}"
        assert os.path.isfile(success_log), "test.py did not create success.log"
        with open(success_log) as f:
            assert f.read() == "Proxy and API functional", "success.log must contain the exact required string"
    finally:
        if spy is not None:
            spy.terminate()
            try:
                spy.wait(timeout=3)
            except subprocess.TimeoutExpired:
                spy.kill()
        subprocess.Popen(["nginx", "-c", NGINX_CONF], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert wait_for_port(True, 5), "Failed to restart nginx with /home/user/app/nginx.conf"


def test_success_log():
    """Verify success log exists and has correct content."""
    log_path = os.path.join(APP, "success.log")
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did you run your test script?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "Proxy and API functional" in content, f"Expected 'Proxy and API functional' in {log_path}, got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
