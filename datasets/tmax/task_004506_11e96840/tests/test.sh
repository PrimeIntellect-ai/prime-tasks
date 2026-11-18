#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'BACKEND_EOF' > /tmp/verifier_backend.py
import json
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

port = int(sys.argv[1])
kind = sys.argv[2]
record_path = sys.argv[3]

class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(record_path, "a", encoding="utf-8") as f:
            f.write(self.path + "\n")
            f.flush()

        query = parse_qs(urlparse(self.path).query, keep_blank_values=True)
        user_id = query.get("id", [""])[0]
        numeric_id = int(user_id) if user_id.isdigit() else 0

        if kind == "legacy":
            response = {
                "user_id": numeric_id,
                "first_name": "Alice",
                "account_data": {
                    "created_at": "2023-01-01",
                    "item_list": [
                        {"deep_key": "deepValue", "second_level_key": 7}
                    ]
                }
            }
        else:
            response = {
                "userId": numeric_id,
                "firstName": "Alice_New" if user_id in ("555", "902") else "Alice",
                "accountData": {
                    "createdAt": "2023-01-01",
                    "itemList": [
                        {"deepKey": "deepValue", "secondLevelKey": 7}
                    ]
                }
            }

        body = json.dumps(response).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass

ReusableHTTPServer(("127.0.0.1", port), Handler).serve_forever()
BACKEND_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import signal
import socket
import subprocess
import time
import urllib.request

import pytest

WORKSPACE_DIR = "/home/user/migration_test"
PROXY_PATH = os.path.join(WORKSPACE_DIR, "proxy.go")
PROFILE_PATH = os.path.join(WORKSPACE_DIR, "mem.prof")
LOG_PATH = os.path.join(WORKSPACE_DIR, "diff_results.log")
LEGACY_RECORD = "/tmp/verifier_legacy_paths.log"
NEW_RECORD = "/tmp/verifier_new_paths.log"


def kill_port_listeners(ports):
    wanted_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state != "0A":
                        continue
                    port = int(local.rsplit(":", 1)[1], 16)
                    if port in ports:
                        wanted_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = os.path.join("/proc", name, "fd")
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in wanted_inodes:
                    victims.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError(f"port {port} did not become ready")


def request(path):
    with urllib.request.urlopen("http://127.0.0.1:8080" + path, timeout=8) as response:
        response.read()
        assert response.status < 500


def wait_for_record(path, exact_value, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as f:
                if exact_value in f.read().splitlines():
                    return
        time.sleep(0.05)
    raise AssertionError(f"backend did not receive exact path {exact_value!r}")


def wait_for_log_text(text, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.isfile(LOG_PATH):
            with open(LOG_PATH, "r", encoding="utf-8") as f:
                content = f.read()
            if text in content:
                return content
        time.sleep(0.05)
    raise AssertionError(f"diff log never contained {text!r}")


def fetch_heap(path):
    with urllib.request.urlopen("http://127.0.0.1:8080/debug/pprof/heap?gc=1", timeout=15) as response:
        data = response.read()
    assert data[:2] == b"\x1f\x8b", "pprof heap endpoint did not return a gzip profile"
    with open(path, "wb") as f:
        f.write(data)


def profile_total_bytes(path):
    result = subprocess.run(
        ["go", "tool", "pprof", "-top", "-sample_index=inuse_space", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"go tool pprof rejected {path}:\n{result.stdout}"
    match = re.search(r"of\s+([0-9.]+)\s*(B|kB|KB|MB|GB|KiB|MiB|GiB)\s+total", result.stdout)
    assert match, f"could not determine heap size from pprof output:\n{result.stdout}"
    value = float(match.group(1))
    unit = match.group(2)
    factors = {
        "B": 1,
        "kB": 1024,
        "KB": 1024,
        "KiB": 1024,
        "MB": 1024 ** 2,
        "MiB": 1024 ** 2,
        "GB": 1024 ** 3,
        "GiB": 1024 ** 3,
    }
    return value * factors[unit]


@pytest.fixture(scope="session", autouse=True)
def running_submission():
    kill_port_listeners({8022, 8033, 8080})
    for path in (LEGACY_RECORD, NEW_RECORD):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["go", "build", "-o", "/tmp/submitted_proxy", "./proxy.go"],
        cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"proxy.go does not build:\n{build.stdout}"

    processes = [
        subprocess.Popen(["python3", "/tmp/verifier_backend.py", "8022", "legacy", LEGACY_RECORD], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL),
        subprocess.Popen(["python3", "/tmp/verifier_backend.py", "8033", "new", NEW_RECORD], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL),
    ]
    try:
        wait_for_port(8022)
        wait_for_port(8033)
        processes.append(subprocess.Popen(["/tmp/submitted_proxy"], cwd=WORKSPACE_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        wait_for_port(8080)
        yield
        assert processes[-1].poll() is None, "the submitted proxy exited during verification"
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
        for process in reversed(processes):
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()


def test_memory_leak_fixed():
    assert os.path.isfile(PROXY_PATH), f"{PROXY_PATH} does not exist."
    with open(PROXY_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "GlobalLeakTracker = append" not in content, "The memory leak in proxy.go was not fixed (GlobalLeakTracker = append still exists)."


def test_memory_profile_generated():
    assert os.path.isfile(PROFILE_PATH), f"Memory profile {PROFILE_PATH} was not generated."
    try:
        with gzip.open(PROFILE_PATH, "rb") as f:
            assert f.read(1), "profile is empty"
    except Exception as exc:
        pytest.fail(f"{PROFILE_PATH} is not a valid gzip-compressed file (expected pprof format): {exc}")

    result = subprocess.run(
        ["go", "tool", "pprof", "-top", PROFILE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"mem.prof is not a valid Go pprof profile:\n{result.stdout}"


def test_routing_recursive_conversion_and_unified_diff():
    open(LOG_PATH, "w", encoding="utf-8").close()

    matching_path = "/api/user?id=901&verbose=true&tag=a%2Fb&tag=x+y&empty="
    request(matching_path)
    wait_for_record(LEGACY_RECORD, matching_path)
    wait_for_record(NEW_RECORD, matching_path)
    time.sleep(0.5)
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        assert f.read() == "", "matching recursively converted JSON incorrectly produced a diff"

    mismatch_path = "/api/user?id=902&verbose=false&tag=z%2Fq&empty="
    request(mismatch_path)
    wait_for_record(LEGACY_RECORD, mismatch_path)
    wait_for_record(NEW_RECORD, mismatch_path)
    content = wait_for_log_text("Alice_New")

    assert "Alice" in content and "Alice_New" in content, "The diff log does not contain the expected firstName difference."
    assert "-" in content and "+" in content, "The diff log does not appear to contain a unified diff."
    assert re.search(r"(?m)^---", content), "unified diff is missing its old-file header"
    assert re.search(r"(?m)^\+\+\+", content), "unified diff is missing its new-file header"
    assert re.search(r"(?m)^@@", content), "unified diff is missing a hunk header"
    assert re.search(r'(?m)^-  "firstName": "Alice",?$', content), "legacy JSON was not diffed with 2-space indentation"
    assert re.search(r'(?m)^\+  "firstName": "Alice_New",?$', content), "new JSON was not diffed with 2-space indentation"

    # Execute the supplied traffic script as required and leave its expected diff in the final log.
    open(LOG_PATH, "w", encoding="utf-8").close()
    run = subprocess.run(["bash", "run_requests.sh"], cwd=WORKSPACE_DIR, timeout=20)
    assert run.returncode == 0, "run_requests.sh failed"
    wait_for_record(LEGACY_RECORD, "/api/user?id=123")
    wait_for_record(NEW_RECORD, "/api/user?id=123")
    wait_for_record(LEGACY_RECORD, "/api/user?id=555")
    wait_for_record(NEW_RECORD, "/api/user?id=555")
    final_content = wait_for_log_text("Alice_New")
    assert "Alice" in final_content and "Alice_New" in final_content
    assert re.search(r"(?m)^---", final_content) and re.search(r"(?m)^\+\+\+", final_content)


def test_runtime_does_not_retain_request_megabytes():
    before_path = "/tmp/heap_before.prof"
    after_path = "/tmp/heap_after.prof"
    fetch_heap(before_path)
    before = profile_total_bytes(before_path)

    for i in range(24):
        request(f"/api/user?id=901&leak_probe={i}")

    fetch_heap(after_path)
    after = profile_total_bytes(after_path)
    growth = after - before
    assert growth < 8 * 1024 * 1024, f"heap retained {growth / (1024 * 1024):.1f} MiB after 24 requests; request history is still leaking"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
