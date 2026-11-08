#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import pwd
import secrets
import socket
import stat
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def get_filter_cmd():
    env_file = "/home/user/solution.env"
    if not os.path.exists(env_file):
        return None
    with open(env_file, "r") as f:
        for line in f:
            if line.startswith("FILTER_CMD="):
                val = line.strip().split("=", 1)[1]
                return val.strip('"\'')
    return None


def run_filter(content, timeout=5):
    cmd = get_filter_cmd()
    assert cmd is not None, "Cannot test corpus without FILTER_CMD"
    return subprocess.run([cmd], input=content, text=True, capture_output=True, timeout=timeout)


def semantic_lines(content):
    return [json.loads(line) for line in content.splitlines() if line.strip()]


def user_systemctl(*args, check=False):
    account = pwd.getpwnam("user")
    runtime = f"/run/user/{account.pw_uid}"
    env_args = [
        f"XDG_RUNTIME_DIR={runtime}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus",
    ]
    cmd = ["runuser", "-u", "user", "--", "env", *env_args,
           "systemctl", "--user", *args]
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def show_unit(unit):
    proc = user_systemctl(
        "show", unit, "-p", "After", "-p", "Requires", "-p", "Restart",
        "-p", "RestartUSec", "-p", "ActiveState"
    )
    assert proc.returncode == 0, f"Unable to inspect {unit}: {proc.stderr or proc.stdout}"
    result = {}
    for line in proc.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result


def wait_active(unit, expected="active", timeout=10):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        proc = user_systemctl("is-active", unit)
        last = proc.stdout.strip()
        if last == expected:
            return
        time.sleep(0.25)
    assert False, f"{unit} did not become {expected}; last state was {last!r}"


def test_solution_env_and_filter_executable():
    cmd = get_filter_cmd()
    assert cmd is not None, "FILTER_CMD not found in /home/user/solution.env"
    assert os.path.isabs(cmd), f"FILTER_CMD path '{cmd}' is not absolute"
    assert os.path.exists(cmd), f"Filter script not found at {cmd}"
    assert os.path.isfile(cmd), f"Filter path {cmd} is not a regular file"
    assert os.access(cmd, os.X_OK), f"Filter script at {cmd} is not executable"


def test_original_corpora_filtering():
    evil_dir = "/home/user/app/corpora/evil/"
    clean_dir = "/home/user/app/corpora/clean/"
    evil_files = glob.glob(os.path.join(evil_dir, "*"))
    clean_files = glob.glob(os.path.join(clean_dir, "*"))

    assert evil_files, f"No evil corpus files found in {evil_dir}"
    assert clean_files, f"No clean corpus files found in {clean_dir}"

    evil_bypassed = []
    clean_modified = []
    for path in evil_files:
        content = open(path).read()
        proc = run_filter(content)
        if proc.stdout.strip():
            evil_bypassed.append(os.path.basename(path))

    for path in clean_files:
        content = open(path).read()
        proc = run_filter(content)
        try:
            if semantic_lines(content) != semantic_lines(proc.stdout):
                clean_modified.append(os.path.basename(path))
        except (ValueError, json.JSONDecodeError):
            clean_modified.append(os.path.basename(path))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not errors, " ; ".join(errors)


def test_randomized_mixed_filtering():
    token = secrets.token_hex(16)
    records = [
        {"env": "prod", "cost": 0.01, "token": token + "-keep-a"},
        {"env": "dev", "cost": 812.75, "token": token + "-drop-dev"},
        {"env": "prod", "cost": 0, "token": token + "-drop-zero-int"},
        {"env": "test", "cost": 9, "token": token + "-drop-test"},
        {"env": "prod", "cost": None, "token": token + "-drop-null"},
        {"env": "prod", "token": token + "-drop-missing"},
        {"env": "prod", "cost": -3.5, "token": token + "-drop-negative"},
        {"env": "qa", "cost": 44, "token": token + "-drop-other-env"},
        {"env": "prod", "cost": 173, "token": token + "-keep-b", "extra": {"x": 1}},
        {"cost": 7, "token": token + "-drop-missing-env"},
    ]
    # Use non-fixture formatting and exercise a mixed stream in one invocation.
    lines = [json.dumps(r, separators=(",", ":"), sort_keys=(i % 2 == 0)) for i, r in enumerate(records)]
    content = "\n".join(lines) + "\n"
    proc = run_filter(content)
    assert proc.returncode == 0, f"Filter exited with {proc.returncode}: {proc.stderr}"
    try:
        actual = semantic_lines(proc.stdout)
    except (ValueError, json.JSONDecodeError) as exc:
        assert False, f"Filter emitted invalid JSON-lines: {exc}"
    expected = [records[0], records[8]]
    assert actual == expected, f"Randomized predicate test expected {expected!r}, got {actual!r}"


def test_systemd_configuration_and_running_state():
    aggregator = show_unit("cost-aggregator.service")
    after = aggregator.get("After", "").split()
    requires = aggregator.get("Requires", "").split()
    assert "billing-receiver.service" in after, "cost-aggregator.service lacks After=billing-receiver.service"
    assert "billing-receiver.service" in requires, "cost-aggregator.service lacks Requires=billing-receiver.service"
    assert aggregator.get("Restart") == "always", "cost-aggregator.service is missing Restart=always"
    assert aggregator.get("RestartUSec") == "5s", "cost-aggregator.service is missing RestartSec=5"

    for unit in ("billing-receiver.service", "log-generator.service", "cost-aggregator.service"):
        state = show_unit(unit).get("ActiveState")
        assert state == "active", f"{unit} is not running (ActiveState={state!r})"


def test_pipeline_source_and_live_end_to_end():
    script_path = "/home/user/app/run-aggregator.sh"
    assert os.path.exists(script_path), f"Aggregator script not found at {script_path}"
    content = open(script_path).read()
    cmd = get_filter_cmd()
    assert cmd is not None, "Cannot verify pipeline without FILTER_CMD"
    basename = os.path.basename(cmd)
    assert cmd in content or basename in content, f"run-aggregator.sh does not appear to pipe through the cost-filter ({basename})"

    # Stop the managed processes temporarily so the submitted wrapper can be
    # exercised against a counting receiver on the actual billing port.
    for unit in ("cost-aggregator.service", "log-generator.service", "billing-receiver.service"):
        user_systemctl("stop", unit)

    received = []
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length).decode("utf-8", errors="replace")
            with lock:
                received.append(body)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

        def log_message(self, fmt, *args):
            pass

    server = None
    wrapper = None
    try:
        deadline = time.time() + 5
        while True:
            try:
                server = ThreadingHTTPServer(("127.0.0.1", 8080), Handler)
                break
            except OSError:
                if time.time() >= deadline:
                    raise
                time.sleep(0.2)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        open("/home/user/app/usage.log", "w").close()
        wrapper = subprocess.Popen(
            ["runuser", "-u", "user", "--", script_path],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        time.sleep(0.6)

        marker = secrets.token_hex(16)
        clean_a = marker + "-clean-a"
        clean_b = marker + "-clean-b"
        evil = [marker + "-dev", marker + "-zero", marker + "-missing"]
        events = [
            {"env": "dev", "cost": 91, "token": evil[0]},
            {"env": "prod", "cost": 2.75, "token": clean_a},
            {"env": "prod", "cost": 0, "token": evil[1]},
            {"env": "prod", "token": evil[2]},
            {"env": "prod", "cost": 6, "token": clean_b},
        ]
        with open("/home/user/app/usage.log", "a") as log:
            for event in events:
                log.write(json.dumps(event, separators=(",", ":")) + "\n")
            log.flush()

        deadline = time.time() + 10
        while time.time() < deadline:
            with lock:
                combined = "\n".join(received)
            if clean_a in combined and clean_b in combined:
                break
            if wrapper.poll() is not None:
                break
            time.sleep(0.2)

        # Give rejected records an additional opportunity to arrive.
        time.sleep(1)
        with lock:
            combined = "\n".join(received)
        assert clean_a in combined and clean_b in combined, \
            f"Live pipeline did not deliver both billable records; received: {received!r}"
        for bad in evil:
            assert bad not in combined, f"Live pipeline delivered non-billable record {bad}"
    finally:
        if wrapper is not None and wrapper.poll() is None:
            wrapper.terminate()
            try:
                wrapper.wait(timeout=3)
            except subprocess.TimeoutExpired:
                wrapper.kill()
        if server is not None:
            server.shutdown()
            server.server_close()
        for unit in ("billing-receiver.service", "log-generator.service", "cost-aggregator.service"):
            user_systemctl("start", unit)
        for unit in ("billing-receiver.service", "log-generator.service", "cost-aggregator.service"):
            wait_active(unit)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
