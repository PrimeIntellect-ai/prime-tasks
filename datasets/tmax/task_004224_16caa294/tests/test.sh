#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time

import pytest
import requests

APP_DIR = "/home/user/app"
BASHRC_PATH = "/home/user/.bashrc"
START_SCRIPT = os.path.join(APP_DIR, "start_all.sh")
NGINX_CONFIG = os.path.join(APP_DIR, "nginx.conf")


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except (OSError, ValueError):
        return ""


def proc_environ(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            entries = f.read().split(b"\0")
        result = {}
        for entry in entries:
            if b"=" in entry:
                key, value = entry.split(b"=", 1)
                result[key.decode(errors="replace")] = value.decode(errors="replace")
        return result
    except (OSError, ValueError):
        return {}


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local_address = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    try:
                        local_port = int(local_address.rsplit(":", 1)[1], 16)
                    except (ValueError, IndexError):
                        continue
                    if local_port == port and state == "0A":
                        inodes.add(inode)
        except OSError:
            pass

    pids = set()
    if not inodes:
        return pids
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            continue
    return pids


def wait_for(predicate, timeout=10, interval=0.2):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return None


def test_bashrc_env_vars():
    """Verify required variables are exported in .bashrc and active in the analyzer."""
    assert os.path.isfile(BASHRC_PATH), f"{BASHRC_PATH} does not exist."
    with open(BASHRC_PATH, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "FINOPS_API_KEY=opt-cost-2024" in content or "FINOPS_API_KEY=\"opt-cost-2024\"" in content or "FINOPS_API_KEY='opt-cost-2024'" in content, "FINOPS_API_KEY is not correctly set in .bashrc"
    assert "DATASTORE_HOST" in content, "DATASTORE_HOST is not set in .bashrc"
    assert "DATASTORE_PORT" in content, "DATASTORE_PORT is not set in .bashrc"

    assert re.search(r"(?m)^\s*export\s+FINOPS_API_KEY\s*=\s*(['\"]?)opt-cost-2024\1\s*(?:#.*)?$", content)
    assert re.search(r"(?m)^\s*export\s+DATASTORE_PORT\s*=\s*(['\"]?)9092\1\s*(?:#.*)?$", content)
    assert re.search(r"(?m)^\s*export\s+DATASTORE_HOST\s*=\s*(['\"]?)(?:localhost|127\.0\.0\.1)\1\s*(?:#.*)?$", content)

    analyzer_pids = listener_pids(9091)
    analyzer_pid = next((p for p in analyzer_pids if "cost_analyzer.py" in proc_cmdline(p)), None)
    assert analyzer_pid is not None, "Port 9091 is not served by cost_analyzer.py"
    env = proc_environ(analyzer_pid)
    assert env.get("FINOPS_API_KEY") == "opt-cost-2024", "FINOPS_API_KEY is not active in cost_analyzer.py"
    assert env.get("DATASTORE_PORT") == "9092", "DATASTORE_PORT is not active in cost_analyzer.py"
    assert env.get("DATASTORE_HOST") in ("localhost", "127.0.0.1"), "DATASTORE_HOST is not active in cost_analyzer.py"


def test_start_script_exists_and_executable():
    """Verify start_all.sh exists, is executable, and has a live monitoring loop."""
    assert os.path.isfile(START_SCRIPT), f"{START_SCRIPT} does not exist."
    assert os.access(START_SCRIPT, os.X_OK), f"{START_SCRIPT} is not executable."

    with open(START_SCRIPT, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "while" in content or "until" in content, f"{START_SCRIPT} does not seem to contain a monitoring loop."
    assert "8080" in content, "The monitoring script does not check Nginx on port 8080"
    assert "9091" in content, "The monitoring script does not check the analyzer on port 9091"

    live_script = any(
        START_SCRIPT in proc_cmdline(int(name))
        for name in os.listdir("/proc") if name.isdigit()
    )
    assert live_script, "start_all.sh is not currently running"


def test_nginx_configuration_and_live_components():
    assert os.path.isfile(NGINX_CONFIG), f"{NGINX_CONFIG} does not exist"
    with open(NGINX_CONFIG) as f:
        config = f.read()

    assert re.search(r"\blisten\s+8080\b", config), "Nginx is not configured to listen on port 8080"
    assert re.search(r"\bpid\s+/home/user/app/nginx\.pid\s*;", config), "Nginx PID path is incorrect"
    assert re.search(r"\berror_log\s+/home/user/app/error\.log(?:\s+\w+)?\s*;", config), "Nginx error log path is incorrect"
    assert "/api/v1/costs" in config, "Nginx has no /api/v1/costs route"
    assert "proxy_pass" in config, "Nginx configuration has no reverse proxy"

    checked = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONFIG],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert checked.returncode == 0, f"nginx.conf is invalid:\n{checked.stdout}"

    nginx_pids = listener_pids(8080)
    assert nginx_pids and any("nginx" in proc_cmdline(p).lower() for p in nginx_pids), "Port 8080 is not served by Nginx"
    analyzer_pids = listener_pids(9091)
    assert analyzer_pids and any("cost_analyzer.py" in proc_cmdline(p) for p in analyzer_pids), "Port 9091 is not served by cost_analyzer.py"
    datastore_pids = listener_pids(9092)
    assert datastore_pids and any("billing_datastore.py" in proc_cmdline(p) for p in datastore_pids), "Port 9092 is not served by billing_datastore.py"


def test_api_endpoint():
    """Preserve the original fixed end-to-end API assertions."""
    url = "http://localhost:8080/api/v1/costs"
    max_retries = 5
    response = None
    for _ in range(max_retries):
        try:
            response = requests.get(url, timeout=2)
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)

    assert response is not None, f"Failed to connect to {url}"
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data.get("status") == "optimized", f"Expected status 'optimized', got {data.get('status')}"
    assert "data" in data, "Response JSON missing 'data' key"
    assert data["data"].get("cloud_cost") == 420.50, f"Expected cloud_cost 420.50, got {data['data'].get('cloud_cost')}"


def test_dynamic_dependency_chain_and_nginx_restart_monitoring():
    """Use an unpredictable datastore result, then prove the monitor restarts Nginx."""
    datastore_pids = listener_pids(9092)
    billing_pids = [p for p in datastore_pids if "billing_datastore.py" in proc_cmdline(p)]
    assert billing_pids, "No running billing_datastore.py was found"
    for pid in billing_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    assert wait_for(lambda: not listener_pids(9092), timeout=8), "The original datastore did not release port 9092"

    dynamic_cost = random.randint(100001, 900000) / 100.0
    tempdir = tempfile.mkdtemp(prefix="finops_verify_")
    observed_path = os.path.join(tempdir, "observed.json")
    mock_path = os.path.join(tempdir, "dynamic_datastore.py")
    with open(mock_path, "w") as f:
        f.write(f'''from http.server import BaseHTTPRequestHandler, HTTPServer\nimport json\nOBSERVED = {observed_path!r}\nVALUE = {dynamic_cost!r}\nclass Handler(BaseHTTPRequestHandler):\n    def do_GET(self):\n        auth = self.headers.get("Authorization")\n        with open(OBSERVED, "w") as out:\n            json.dump({{"path": self.path, "authorization": auth}}, out)\n        if self.path == "/internal/metrics" and auth == "Bearer opt-cost-2024":\n            self.send_response(200)\n            self.send_header("Content-Type", "application/json")\n            self.end_headers()\n            self.wfile.write(json.dumps({{"cloud_cost": VALUE}}).encode())\n        else:\n            self.send_response(403)\n            self.end_headers()\n    def log_message(self, *args):\n        pass\nHTTPServer(("127.0.0.1", 9092), Handler).serve_forever()\n''')

    mock = subprocess.Popen([sys.executable, mock_path])
    try:
        assert wait_for(lambda: listener_pids(9092), timeout=5), "Dynamic datastore failed to start"

        response = requests.get("http://localhost:8080/api/v1/costs", timeout=5)
        assert response.status_code == 200, response.text
        payload = response.json()
        assert payload.get("status") == "optimized"
        assert payload.get("data", {}).get("cloud_cost") == dynamic_cost, "The response did not propagate the unpredictable datastore value"
        assert os.path.isfile(observed_path), "The analyzer never contacted the datastore"
        with open(observed_path) as f:
            observed = json.load(f)
        assert observed == {"path": "/internal/metrics", "authorization": "Bearer opt-cost-2024"}, "The analyzer used the wrong datastore request or API key"

        pid_path = os.path.join(APP_DIR, "nginx.pid")
        assert os.path.isfile(pid_path), "Configured Nginx PID file is missing"
        with open(pid_path) as f:
            old_master = int(f.read().strip())
        assert "nginx" in proc_cmdline(old_master).lower(), "nginx.pid does not identify the live Nginx master"
        os.kill(old_master, signal.SIGTERM)

        def restarted_master():
            try:
                with open(pid_path) as f:
                    new_pid = int(f.read().strip())
                if new_pid != old_master and "nginx" in proc_cmdline(new_pid).lower() and listener_pids(8080):
                    return new_pid
            except (OSError, ValueError):
                pass
            return None

        new_master = wait_for(restarted_master, timeout=20, interval=0.5)
        assert new_master, "start_all.sh did not restart Nginx after its master process died"

        response = requests.get("http://localhost:8080/api/v1/costs", timeout=5)
        assert response.status_code == 200, response.text
        assert response.json().get("data", {}).get("cloud_cost") == dynamic_cost, "The restarted Nginx is not proxying to the analyzer"
        assert any("nginx" in proc_cmdline(p).lower() for p in listener_pids(8080)), "The restarted port 8080 listener is not Nginx"
    finally:
        mock.terminate()
        try:
            mock.wait(timeout=3)
        except subprocess.TimeoutExpired:
            mock.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
