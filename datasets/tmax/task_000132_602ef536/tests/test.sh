#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0
mock_pid=""
cleanup() {
    if [ -n "$mock_pid" ]; then
        kill "$mock_pid" 2>/dev/null || true
        wait "$mock_pid" 2>/dev/null || true
    fi
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT

# Replace the unobservable mock API with an instrumented equivalent.
pkill -f '[/]app/k8s_mock.py' 2>/dev/null || true
sleep 0.2

cat <<'PY_EOF' > /tmp/verifier_k8s_mock.py
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

records = []
lock = threading.Lock()

class Server(ThreadingHTTPServer):
    request_queue_size = 1024
    daemon_threads = True

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def send_body(self, status, body, content_type="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        if self.path == "/__reset":
            with lock:
                records.clear()
            self.send_body(200, b"{}")
            return

        with lock:
            records.append({
                "method": "POST",
                "path": self.path,
                "content_type": self.headers.get("Content-Type", ""),
                "body": body.decode("utf-8", errors="replace"),
                "received_at": time.time(),
            })
            count = len(records)
        self.send_body(200, json.dumps({"status": "ok", "count": count}, separators=(",", ":")).encode())

    def do_GET(self):
        if self.path == "/__records":
            with lock:
                body = json.dumps(records, separators=(",", ":")).encode()
            self.send_body(200, body)
            return
        if self.path == "/sync":
            with lock:
                records.append({
                    "method": "GET",
                    "path": self.path,
                    "content_type": "",
                    "body": "",
                    "received_at": time.time(),
                })
            # Match Flask jsonify's newline-terminated response.
            self.send_body(200, b'{"status":"synced"}\n')
            return
        self.send_body(404, b'{"error":"not found"}\n')

Server(("127.0.0.1", 9090), Handler).serve_forever()
PY_EOF

python3 /tmp/verifier_k8s_mock.py >/tmp/verifier_k8s_mock.log 2>&1 &
mock_pid=$!

ready=0
for _ in $(seq 1 50); do
    if curl -fsS http://127.0.0.1:9090/__records >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 0.1
done
if [ "$ready" -ne 1 ]; then
    exit 0
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import tempfile
import time
import urllib.request
import uuid

HOOK = "/home/user/gitserver/manifests.git/hooks/post-receive"
API = "http://127.0.0.1:9090"


def api_request(path, method="GET"):
    req = urllib.request.Request(API + path, data=(b"" if method == "POST" else None), method=method)
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.read()


def reset_records():
    api_request("/__reset", "POST")


def get_records():
    return json.loads(api_request("/__records").decode("utf-8"))


def assert_yaml_posts(expected, push_finished_at=None):
    records = get_records()
    assert len(records) == len(expected), f"Expected {len(expected)} API requests, got {len(records)}"
    actual = {}
    for record in records:
        assert record["method"] == "POST", f"Expected POST, got {record['method']}"
        assert record["path"] == "/apply", f"Expected /apply, got {record['path']}"
        assert record["content_type"].lower() == "application/yaml", \
            f"Wrong Content-Type: {record['content_type']!r}"
        body = record["body"]
        assert body not in actual, "A YAML manifest was posted more than once"
        actual[body] = True
        if push_finished_at is not None:
            assert record["received_at"] <= push_finished_at, \
                "An apply request completed only after git push had returned"
    assert set(actual) == set(expected.values()), "Posted YAML bodies do not match the committed files"


def test_post_receive_hook_exists():
    assert os.path.isfile(HOOK), f"Hook not found at {HOOK}"
    assert os.access(HOOK, os.X_OK), f"Hook at {HOOK} is not executable"
    with open(HOOK, "rb") as f:
        assert f.read(4) == b"\x7fELF", "post-receive must be a compiled native executable"


def test_performance_and_functionality():
    nonce = uuid.uuid4().hex
    branch = "audit-" + nonce
    with tempfile.TemporaryDirectory() as repo_dir:
        subprocess.check_call(["git", "init", repo_dir], stdout=subprocess.DEVNULL)
        subprocess.check_call(["git", "config", "user.name", "Test User"], cwd=repo_dir)
        subprocess.check_call(["git", "config", "user.email", "test@example.com"], cwd=repo_dir)
        subprocess.check_call([
            "git", "remote", "add", "origin", "http://127.0.0.1:8000/manifests.git"
        ], cwd=repo_dir)

        expected = {}
        for i in range(500):
            body = f"apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: cm-{nonce}-{i}\n"
            name = f"manifest_{nonce}_{i}.yaml"
            expected[name] = body
            with open(os.path.join(repo_dir, name), "w") as f:
                f.write(body)

        subprocess.check_call(["git", "add", "."], cwd=repo_dir)
        subprocess.check_call(["git", "commit", "-m", "Add 500 manifests"], cwd=repo_dir,
                              stdout=subprocess.DEVNULL)
        reset_records()
        started = time.perf_counter()
        subprocess.check_call(["git", "push", "origin", f"HEAD:refs/heads/{branch}"], cwd=repo_dir,
                              stdout=subprocess.DEVNULL)
        elapsed = time.perf_counter() - started
        push_finished_at = time.time()
        assert elapsed <= 1.5, f"git push took {elapsed:.3f} seconds, which exceeds the 1.5 second threshold"
        assert_yaml_posts(expected, push_finished_at)

        # Exercise modified and newly added YAML files, while ensuring deleted YAML
        # and changed non-YAML files are not submitted.
        changed = {}
        for i in range(3):
            name = f"manifest_{nonce}_{i}.yaml"
            body = f"apiVersion: v1\nkind: Secret\nmetadata:\n  name: changed-{nonce}-{i}\n"
            with open(os.path.join(repo_dir, name), "w") as f:
                f.write(body)
            changed[name] = body

        added_name = f"new_{nonce}.yaml"
        added_body = f"apiVersion: v1\nkind: Service\nmetadata:\n  name: new-{nonce}\n"
        with open(os.path.join(repo_dir, added_name), "w") as f:
            f.write(added_body)
        changed[added_name] = added_body

        os.remove(os.path.join(repo_dir, f"manifest_{nonce}_10.yaml"))
        with open(os.path.join(repo_dir, "ignored.txt"), "w") as f:
            f.write("this is not YAML\n")

        subprocess.check_call(["git", "add", "-A"], cwd=repo_dir)
        subprocess.check_call(["git", "commit", "-m", "Modify manifests"], cwd=repo_dir,
                              stdout=subprocess.DEVNULL)
        reset_records()
        subprocess.check_call(["git", "push", "origin", f"HEAD:refs/heads/{branch}"], cwd=repo_dir,
                              stdout=subprocess.DEVNULL)
        second_finished_at = time.time()
        assert_yaml_posts(changed, second_finished_at)


def test_cron_job_configured_and_executable():
    try:
        crontab = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT).decode("utf-8")
    except subprocess.CalledProcessError:
        crontab = ""

    # Preserve the original assertions.
    assert "9090/sync" in crontab, "Cron job for /sync endpoint is not configured correctly"
    assert "sync.log" in crontab, "Cron job does not append to /home/user/sync.log"

    candidates = []
    for raw in crontab.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("@"):
            continue
        parts = line.split(None, 5)
        if len(parts) != 6:
            continue
        minute, hour, dom, month, dow, command = parts
        minute_every = minute in ("*", "*/1", "0-59", "0-59/1")
        if minute_every and hour == dom == month == dow == "*" and \
                "9090/sync" in command and "sync.log" in command:
            candidates.append(command)
    assert candidates, "No valid every-minute /sync cron command was found"

    command = candidates[0]
    log_path = "/home/user/sync.log"
    marker = "existing-log-entry\n"
    with open(log_path, "w") as f:
        f.write(marker)

    reset_records()
    subprocess.run(["/bin/sh", "-c", command], check=True, timeout=10)
    subprocess.run(["/bin/sh", "-c", command], check=True, timeout=10)

    with open(log_path, "rb") as f:
        contents = f.read()
    expected = marker.encode() + b'{"status":"synced"}\n' * 2
    assert contents == expected, "Cron command must append each /sync response with a newline"

    records = get_records()
    assert len(records) == 2, f"Expected two sync requests, got {len(records)}"
    assert all(r["method"] == "GET" and r["path"] == "/sync" for r in records), \
        "Cron command did not execute HTTP GET requests to /sync"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
