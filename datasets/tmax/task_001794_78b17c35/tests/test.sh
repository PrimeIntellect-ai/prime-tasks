#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import hashlib
import json
import os
import re
import secrets
import signal
import subprocess
import time

import pytest

SUPERCRONIC = "/home/user/bin/supercronic"
SYNC_BINARY = "/home/user/bin/sync_users"
SYNC_SOURCE = "/home/user/sync_users.go"
CSV_PATH = "/home/user/data/users.csv"
JSON_PATH = "/home/user/sync_out.json"
CRON_PATH = "/home/user/sync.cron"


def go_binary(path):
    result = subprocess.run(["go", "version", "-m", path], capture_output=True, text=True)
    assert result.returncode == 0, f"{path} is not a compiled Go executable: {result.stderr}"
    assert "go1." in result.stdout, f"{path} lacks Go build information."


def expected_records(csv_path):
    result = collections.Counter()
    with open(csv_path, newline="", encoding="utf-8") as f:
        for row_number, row in enumerate(csv.reader(f), 1):
            assert len(row) == 2, f"CSV row {row_number} does not have two columns."
            username, role = row
            digest = hashlib.sha256((username + role).encode("utf-8")).hexdigest()
            result[(username, role, digest)] += 1
    return result


def assert_json_matches_csv(csv_path=CSV_PATH, json_path=JSON_PATH):
    assert os.path.isfile(json_path), f"{json_path} does not exist."
    try:
        with open(json_path, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"{json_path} is not valid JSON: {exc}")

    assert isinstance(data, list), "sync_out.json must contain a JSON array."
    assert len(data) == 200000, f"Expected 200000 records, found {len(data)}."

    actual = collections.Counter()
    for index, item in enumerate(data):
        assert isinstance(item, dict), f"Record {index} is not an object."
        assert "username" in item, "Missing 'username' key in JSON objects."
        assert "role" in item, "Missing 'role' key in JSON objects."
        assert "hash" in item, "Missing 'hash' key in JSON objects."
        assert isinstance(item["username"], str), f"Record {index} has a non-string username."
        assert isinstance(item["role"], str), f"Record {index} has a non-string role."
        assert isinstance(item["hash"], str), f"Record {index} has a non-string hash."
        calculated = hashlib.sha256((item["username"] + item["role"]).encode("utf-8")).hexdigest()
        assert item["hash"] == calculated, f"Incorrect hash for record {index}."
        actual[(item["username"], item["role"], item["hash"])] += 1

    assert actual == expected_records(csv_path), "JSON records do not exactly match users.csv."


def stop_nc():
    subprocess.run(["pkill", "-x", "nc"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.1)


def start_listener(port):
    process = subprocess.Popen(
        ["nc", "-l", "-p", str(port)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.15)
    assert process.poll() is None, f"Could not start listener on port {port}."
    return process


def terminate(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)


def run_with_listeners(command, timeout=10):
    stop_nc()
    listeners = [start_listener(5900), start_listener(8080)]
    try:
        return subprocess.run(command, capture_output=True, timeout=timeout)
    finally:
        for listener in listeners:
            terminate(listener)
        stop_nc()


def write_random_csv():
    seed = secrets.token_hex(16)
    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        for i in range(200000):
            token = hashlib.sha256(f"{seed}:{i}".encode()).hexdigest()[:18]
            role = ["admin", "user", "auditor", "operator"][int(token[-1], 16) % 4]
            writer.writerow([f"audit_{token}_{i}", role])


def test_final_state():
    # Preserve the original artifact, executable, cron, and initial-output assertions.
    for path in (SUPERCRONIC, SYNC_BINARY):
        assert os.path.isfile(path), f"{path} does not exist."
        assert os.access(path, os.X_OK), f"{path} is not executable."

    assert os.path.isfile(CRON_PATH), f"{CRON_PATH} does not exist."
    with open(CRON_PATH, encoding="utf-8") as f:
        cron_content = f.read()
    assert "* * * * *" in cron_content, f"Expected '* * * * *' schedule in {CRON_PATH}."
    active_lines = [line.strip() for line in cron_content.splitlines()
                    if line.strip() and not line.lstrip().startswith("#")]
    assert any(re.match(r"^\*\s+\*\s+\*\s+\*\s+\*\s+.*(?:/home/user/bin/)?sync_users(?:\s|$)", line)
               for line in active_lines), "sync.cron does not schedule the compiled sync_users binary every minute."

    assert os.path.isfile(SYNC_SOURCE), f"{SYNC_SOURCE} does not exist."
    with open(SYNC_SOURCE, encoding="utf-8") as f:
        source = f.read()
    assert re.search(r"(?m)^\s*go\s+(?:func\s*\(|[A-Za-z_][\w.]*\s*\()", source), \
        "sync_users.go does not launch any goroutine."

    go_binary(SUPERCRONIC)
    go_binary(SYNC_BINARY)

    # Confirm the deliberate source and Makefile perturbations were actually repaired.
    main_go = "/app/supercronic/main.go"
    makefile = "/app/supercronic/Makefile"
    assert os.path.isfile(main_go), f"{main_go} does not exist."
    assert os.path.isfile(makefile), f"{makefile} does not exist."
    with open(main_go, encoding="utf-8") as f:
        runner_source = f.read()
    assert "/tmp/wrongpath" not in runner_source, "The supercronic PATH override is still present."
    with open(makefile, encoding="utf-8") as f:
        make_text = f.read()
    assert re.search(r"(?m)^build\s*:", make_text), "Makefile has no correctly named build target."
    assert not re.search(r"(?m)^bulid\s*:", make_text), "The misspelled Makefile target remains."
    local_runner = "/app/supercronic/supercronic"
    if os.path.exists(local_runner):
        os.remove(local_runner)
    make_result = subprocess.run(["make", "build"], cwd="/app/supercronic", capture_output=True, text=True)
    assert make_result.returncode == 0, f"make build failed: {make_result.stdout}\n{make_result.stderr}"
    assert os.path.isfile(local_runner) and os.access(local_runner, os.X_OK), \
        "The repaired Makefile did not build supercronic."

    # Retain and strengthen the initial JSON check by comparing every row to the CSV.
    assert_json_matches_csv()

    # Each required endpoint must independently be mandatory, with exact failure status 1.
    stop_nc()
    only_5900 = start_listener(5900)
    try:
        failed = subprocess.run([SYNC_BINARY], capture_output=True, timeout=5)
        assert failed.returncode == 1, "sync_users must exit 1 when localhost:8080 is unreachable."
    finally:
        terminate(only_5900)
        stop_nc()

    only_8080 = start_listener(8080)
    try:
        failed = subprocess.run([SYNC_BINARY], capture_output=True, timeout=5)
        assert failed.returncode == 1, "sync_users must exit 1 when localhost:5900 is unreachable."
    finally:
        terminate(only_8080)
        stop_nc()

    # Replace the known dataset with verifier-generated input, then time and fully validate it.
    write_random_csv()
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    start = time.monotonic()
    result = run_with_listeners([SYNC_BINARY], timeout=5)
    elapsed = time.monotonic() - start
    assert result.returncode == 0, \
        f"sync_users failed with return code {result.returncode}. Stderr: {result.stderr.decode(errors='replace')}"
    assert elapsed <= 1.5, f"Performance metric failed: took {elapsed:.3f} seconds (threshold: 1.5s)"
    assert_json_matches_csv()

    # Exercise the task runner itself. The unqualified sh and sha256sum commands verify PATH,
    # while the marker proves that supercronic launched sync_users from a cron entry.
    marker = "/tmp/supercronic_verified"
    verify_cron = "/tmp/verify_sync.cron"
    for path in (marker, JSON_PATH):
        if os.path.exists(path):
            os.remove(path)
    with open(verify_cron, "w", encoding="utf-8") as f:
        f.write(f"* * * * * sh -c '{SYNC_BINARY} && sha256sum /dev/null > {marker}'\n")

    stop_nc()
    listeners = [start_listener(5900), start_listener(8080)]
    env = os.environ.copy()
    env["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    runner = subprocess.Popen(
        [SUPERCRONIC, verify_cron],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        start_new_session=True,
    )
    deadline = time.monotonic() + 70
    try:
        while time.monotonic() < deadline and not os.path.isfile(marker):
            if runner.poll() is not None:
                out, err = runner.communicate()
                pytest.fail(f"supercronic exited before running the job: {out.decode(errors='replace')} {err.decode(errors='replace')}")
            time.sleep(0.1)
        assert os.path.isfile(marker), "supercronic did not execute the scheduled command within 70 seconds."
    finally:
        if runner.poll() is None:
            os.killpg(runner.pid, signal.SIGTERM)
            try:
                runner.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(runner.pid, signal.SIGKILL)
                runner.wait(timeout=3)
        for listener in listeners:
            terminate(listener)
        stop_nc()

    assert_json_matches_csv()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
