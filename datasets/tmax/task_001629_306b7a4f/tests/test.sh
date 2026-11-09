#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import datetime
import json
import os
import random
import re
import shlex
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest
from dotenv import dotenv_values

STACK = "/home/user/app/telemetry_stack"
SCRIPT = "/home/user/app/finops_cleaner.py"


def kill_listeners(ports):
    wanted_inodes = set()
    wanted_ports = {f"{port:04X}" for port in ports}
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].rsplit(":", 1)[-1].upper() in wanted_ports:
                        wanted_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in wanted_inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_ports(ports, process, timeout=20):
    deadline = time.time() + timeout
    remaining = set(ports)
    while time.time() < deadline:
        if process.poll() not in (None, 0):
            pytest.fail(f"start.sh exited unsuccessfully with status {process.returncode}")
        for port in list(remaining):
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                    remaining.remove(port)
            except OSError:
                pass
        if not remaining:
            return
        time.sleep(0.2)
    pytest.fail(f"start.sh did not start listeners on ports: {sorted(remaining)}")


def test_telemetry_stack_flow():
    nginx_conf = os.path.join(STACK, "nginx.conf")
    env_path = os.path.join(STACK, ".env")
    start_path = os.path.join(STACK, "start.sh")

    assert os.path.isfile(nginx_conf), "nginx.conf is missing"
    assert os.path.isfile(env_path), ".env is missing"
    assert os.path.isfile(start_path), "start.sh is missing"
    assert os.access(start_path, os.X_OK), "start.sh is not executable"

    env = dotenv_values(env_path)
    assert env.get("REDIS_HOST") in ("localhost", "127.0.0.1"), "REDIS_HOST must target local Redis"
    assert str(env.get("REDIS_PORT")) == "6379", "REDIS_PORT must be 6379"

    nginx_test = subprocess.run(
        ["nginx", "-T", "-c", nginx_conf, "-p", STACK],
        capture_output=True, text=True
    )
    nginx_dump = nginx_test.stdout + "\n" + nginx_test.stderr
    assert nginx_test.returncode == 0, f"Invalid nginx.conf: {nginx_dump}"
    assert re.search(r"\blisten\s+8080\b", nginx_dump), "Nginx is not configured to listen on 8080"
    location = re.search(r"location\s+/api/\s*\{(.*?)\}", nginx_dump, re.S)
    assert location, "Nginx has no /api/ location"
    assert re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000\s*;", location.group(1)), \
        "/api/ is not proxied to the Flask app on port 5000"

    # Do not trust services left running by the submission: stop all listeners and
    # require the submitted startup script to recreate the complete stack.
    kill_listeners({8080, 5000, 6379})
    proc = subprocess.Popen(
        [start_path], cwd=STACK, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    wait_for_ports({8080, 5000, 6379}, proc)

    subprocess.run(["redis-cli", "-p", "6379", "FLUSHDB"], check=True, capture_output=True, text=True)

    url = "http://localhost:8080/api/record"
    test_payload = {"test_key": "test_value", "timestamp": "2024-05-15T12:00:00Z"}
    data = json.dumps(test_payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status in (200, 201), f"Expected successful HTTP status, got {response.status}"
            body = json.loads(response.read().decode("utf-8"))
            assert body.get("status") == "success", f"Unexpected API response: {body}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx or Flask via {url}: {e}")

    redis_check = subprocess.run(
        ["redis-cli", "-p", "6379", "DBSIZE"], capture_output=True, text=True, check=True
    )
    dbsize = int(redis_check.stdout.strip().split()[-1])
    assert dbsize > 0, "Redis DBSIZE is 0. The record was not saved to Redis."

    stored = subprocess.run(
        ["redis-cli", "-p", "6379", "GET", "last_record"],
        capture_output=True, text=True, check=True
    ).stdout.strip()
    assert stored, "The API did not write the expected last_record key"
    assert ast.literal_eval(stored) == test_payload, "Redis does not contain the submitted payload"


def test_finops_cleaner_script():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."

    evil_corpus = "/home/user/tests/evil_corpus"
    clean_corpus = "/home/user/tests/clean_corpus"
    assert os.path.isdir(evil_corpus), f"Evil corpus directory {evil_corpus} is missing."
    assert os.path.isdir(clean_corpus), f"Clean corpus directory {clean_corpus} is missing."

    initial_evil_files = set(os.listdir(evil_corpus))
    initial_clean_files = set(os.listdir(clean_corpus))

    try:
        subprocess.run(["python3", SCRIPT, evil_corpus], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed on evil corpus: {e.stderr}")
    try:
        subprocess.run(["python3", SCRIPT, clean_corpus], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed on clean corpus: {e.stderr}")

    remaining_evil_files = set(os.listdir(evil_corpus))
    remaining_clean_files = set(os.listdir(clean_corpus))
    evil_bypassed = remaining_evil_files.intersection(initial_evil_files)
    clean_modified = initial_clean_files - remaining_clean_files
    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(initial_evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(initial_clean_files)} clean modified (deleted): {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_finops_cleaner_on_generated_directory():
    today = datetime.date(2024, 5, 15)
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix="finops-generated-") as corpus:
        cases = {
            "app-2024-04-14.log": "ordinary old data",             # 31 days old: delete
            "backup-2024-04-15.bak": "ordinary boundary data",     # exactly 30 days: keep
            "app-2024-05-15.log": "DEBUG_LEVEL=7",                 # debug: delete
            "backup-2020-01-01.bak": "AUDIT_TRAIL=true\nDEBUG_LEVEL=9", # audit wins: keep
            f"misc-{rng.randrange(10**8)}.log": "ordinary undated data", # no criterion: keep
            f"ignore-{rng.randrange(10**8)}.txt": "DEBUG_LEVEL=8",       # wrong extension: untouched
        }

        for _ in range(10):
            age = rng.randrange(0, 1500)
            date = today - datetime.timedelta(days=age)
            prefix, ext = rng.choice((("app", "log"), ("backup", "bak")))
            name = f"{prefix}-{date.isoformat()}.{ext}"
            audit = rng.choice((True, False))
            debug = rng.choice((True, False))
            lines = [f"nonce={rng.randrange(10**12)}"]
            if audit:
                lines.append("AUDIT_TRAIL=true")
            if debug:
                lines.append("DEBUG_LEVEL=3")
            cases[name] = "\n".join(lines)

        original = {}
        expected_keep = set()
        expected_delete = set()
        date_pattern = re.compile(r"^(?:app|backup)-(\d{4}-\d{2}-\d{2})\.(?:log|bak)$")
        for name, content in cases.items():
            path = os.path.join(corpus, name)
            with open(path, "w") as f:
                f.write(content)
            original[name] = content.encode()

            if not name.endswith((".log", ".bak")):
                expected_keep.add(name)
                continue
            match = date_pattern.match(name)
            old = bool(match and (today - datetime.date.fromisoformat(match.group(1))).days > 30)
            wasteful = "DEBUG_LEVEL=" in content or old
            if "AUDIT_TRAIL=true" in content or not wasteful:
                expected_keep.add(name)
            else:
                expected_delete.add(name)

        result = subprocess.run(["python3", SCRIPT, corpus], capture_output=True, text=True)
        assert result.returncode == 0, f"Cleaner failed on generated directory: {result.stderr}"
        remaining = set(os.listdir(corpus))
        assert remaining == expected_keep, \
            f"Incorrect generated-corpus result; expected keep={sorted(expected_keep)}, got={sorted(remaining)}"
        for name in expected_keep:
            with open(os.path.join(corpus, name), "rb") as f:
                assert f.read() == original[name], f"Preserved file {name} was modified"

        no_args = subprocess.run(["python3", SCRIPT], capture_output=True, text=True)
        extra_args = subprocess.run(["python3", SCRIPT, corpus, corpus], capture_output=True, text=True)
        assert no_args.returncode != 0, "Cleaner must reject a missing directory argument"
        assert extra_args.returncode != 0, "Cleaner must accept exactly one argument"


def test_cron_job_scheduled():
    try:
        crontab_out = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True).stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. No crontab for user?")

    valid_cron_found = False
    exact_command_found = False
    for line in crontab_out.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 6:
            schedule = " ".join(parts[:5])
            command = " ".join(parts[5:])
            if schedule == "0 2 * * *" and "finops_cleaner.py" in command and "/home/user/production_logs" in command:
                valid_cron_found = True

            if schedule == "0 2 * * *":
                try:
                    argv = shlex.split(command)
                except ValueError:
                    continue
                if len(argv) >= 3 and os.path.basename(argv[0]) == "python3" \
                        and argv[1] == SCRIPT and argv[2] == "/home/user/production_logs":
                    trailing = " ".join(argv[3:])
                    if not trailing or re.fullmatch(r"(?:[012]?>{1,2}\S+|[012]?>&[012]|\s+)*", trailing):
                        exact_command_found = True

    assert valid_cron_found, "Cron job for finops_cleaner.py at 2:00 AM is missing or incorrect."
    assert exact_command_found, "Cron entry does not actually invoke the cleaner with exactly the production directory"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
