#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier-bin

BACKEND=/app/backend.py
BACKUP=/tmp/backend.py.verifier-original
cp "$BACKEND" "$BACKUP"
restore_backend() {
    cp "$BACKUP" "$BACKEND"
    chmod +x "$BACKEND"
}
trap restore_backend EXIT

cat << 'PY_EOF' > "$BACKEND"
#!/usr/bin/env python3
import json
import runpy
import sys

LOG = "/tmp/verifier-backend-events.jsonl"
ORIGINAL = "/tmp/backend.py.verifier-original"

with open(LOG, "a") as f:
    f.write(json.dumps({"event": "start", "pid": __import__("os").getpid(), "argv": sys.argv}) + "\n")

def trace_calls(frame, event, arg):
    if event == "call" and frame.f_code.co_name == "do_GET":
        handler = frame.f_locals.get("self")
        path = getattr(handler, "path", None)
        with open(LOG, "a") as f:
            f.write(json.dumps({"event": "request", "path": path}) + "\n")
    return trace_calls

sys.settrace(trace_calls)
runpy.run_path(ORIGINAL, run_name="__main__")
PY_EOF
chmod +x "$BACKEND"

cat << 'PY_EOF' > /tmp/verifier-bin/nginx
#!/usr/bin/env python3
import json
import os
import sys

with open("/tmp/verifier-nginx-events.jsonl", "a") as f:
    f.write(json.dumps({"pid": os.getpid(), "argv": sys.argv}) + "\n")
os.execv("/usr/sbin/nginx", ["nginx"] + sys.argv[1:])
PY_EOF
chmod +x /tmp/verifier-bin/nginx
rm -f /tmp/verifier-backend-events.jsonl /tmp/verifier-nginx-events.jsonl

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import signal
import subprocess
import time
import urllib.error
import urllib.request
import uuid
import pytest

EXPECTED_SOCKET = "unix:/tmp/secure_app_v4.sock"


def read_json_lines(path):
    if not os.path.exists(path):
        return []
    records = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def pid_is_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def test_nginx_config_updated():
    """Check that the NGINX config was updated with the correct socket path."""
    nginx_conf_path = "/home/user/nginx.conf"
    assert os.path.exists(nginx_conf_path), f"Missing required file: {nginx_conf_path}"

    with open(nginx_conf_path, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert EXPECTED_SOCKET in content, (
        "The nginx.conf does not contain the correct socket path. "
        f"Expected to find: {EXPECTED_SOCKET}"
    )

    uncommented = re.sub(r"#.*", "", content)
    location = re.search(r"location\s+/\s*\{([^{}]*)\}", uncommented, re.S)
    assert location, "nginx.conf has no location / block"
    directives = re.findall(r"\bproxy_pass\s+([^;]+)\s*;", location.group(1))
    assert directives, "The location / block has no proxy_pass directive"
    assert len(directives) == 1, "The location / block must contain one proxy_pass directive"
    assert directives[0].strip() == "http://unix:/tmp/secure_app_v4.sock", (
        "The proxy_pass directive in location / does not use the extracted socket"
    )

    syntax = subprocess.run(
        ["/usr/sbin/nginx", "-t", "-c", nginx_conf_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert syntax.returncode == 0, f"Invalid nginx configuration: {syntax.stderr}"


def test_ci_test_script_metric():
    """Execute the CI script and verify its processes, requests, metric, and cleanup."""
    script_path = "/home/user/ci_test.py"
    assert os.path.exists(script_path), f"Missing required file: {script_path}"
    assert os.path.isfile(script_path), f"Required path is not a file: {script_path}"

    env = os.environ.copy()
    env["PATH"] = "/tmp/verifier-bin:" + env.get("PATH", "")
    probe_path = "/verifier-probe-" + uuid.uuid4().hex

    process = subprocess.Popen(
        ["python3", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    probe_seen = False
    deadline = time.monotonic() + 60
    try:
        while process.poll() is None and time.monotonic() < deadline:
            try:
                urllib.request.urlopen(
                    "http://127.0.0.1:8080" + probe_path,
                    timeout=0.25,
                ).read()
                probe_seen = True
                break
            except urllib.error.HTTPError as exc:
                if exc.code == 404:
                    probe_seen = True
                    break
            except (urllib.error.URLError, TimeoutError, OSError):
                pass
            time.sleep(0.02)

        remaining = max(0.1, deadline - time.monotonic())
        stdout, stderr = process.communicate(timeout=remaining)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()
        pytest.fail("ci_test.py timed out after 60 seconds.")

    result_returncode = process.returncode
    assert result_returncode == 0, (
        f"ci_test.py failed with return code {result_returncode}.\nStderr: {stderr}"
    )

    output = stdout.strip()
    assert output, "ci_test.py produced no standard output."

    # Preserve the original numeric extraction and threshold assertions.
    matches = re.findall(r"[-+]?\d*\.\d+|\d+", output)
    assert matches, f"Could not find a numeric value in ci_test.py output: {output}"
    try:
        metric_value = float(matches[-1])
    except ValueError:
        pytest.fail(f"Could not parse '{matches[-1]}' as a float. Full output: {output}")
    threshold = 0.95
    assert metric_value >= threshold, (
        f"Success rate metric {metric_value} is below the threshold of {threshold}."
    )

    assert re.fullmatch(r"(?:\d+\.\d*|\.\d+)", output), (
        f"ci_test.py must print only one float, but printed: {output!r}"
    )

    backend_events = read_json_lines("/tmp/verifier-backend-events.jsonl")
    nginx_events = read_json_lines("/tmp/verifier-nginx-events.jsonl")

    starts = [e for e in backend_events if e.get("event") == "start"]
    assert starts, "ci_test.py did not start the provided /app/backend.py"
    assert any(e.get("argv", [None, None])[1:] == [EXPECTED_SOCKET] for e in starts), (
        "The backend was not started with the extracted Unix socket path"
    )

    assert nginx_events, "ci_test.py did not start nginx"
    expected_nginx_args = ["nginx", "-c", "/home/user/nginx.conf", "-g", "daemon off;"]
    assert any(e.get("argv") == expected_nginx_args for e in nginx_events), (
        "nginx was not started with the required config and daemon-off arguments"
    )

    requests = [e.get("path") for e in backend_events if e.get("event") == "request"]
    health_count = requests.count("/health")
    assert health_count >= 50, (
        f"The running backend received only {health_count} /health requests; expected 50"
    )
    assert metric_value == 1.0, (
        f"All 50 instrumented health responses were HTTP 200, so the reported rate must be 1.0, not {metric_value}"
    )
    assert probe_seen and probe_path in requests, (
        "The verifier could not confirm that the nginx instance started by ci_test.py proxied requests to the backend"
    )

    time.sleep(0.5)
    started_pids = [e["pid"] for e in starts] + [e["pid"] for e in nginx_events]
    still_alive = [pid for pid in started_pids if pid_is_alive(pid)]
    assert not still_alive, (
        f"ci_test.py did not gracefully terminate all started processes; live PIDs: {still_alive}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
