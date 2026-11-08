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
import csv
import json
import os
import re
import signal
import subprocess
import time
import uuid

import pytest
import requests


def test_pipeline_log_format():
    log_path = "/home/user/pipeline.log"
    assert os.path.exists(log_path), f"Log file missing at {log_path}"
    with open(log_path, "r") as f:
        content = f.read()

    match = re.search(r"\[INFO\] Removed \d+ duplicate records\.", content)
    assert match, "Log file does not contain the expected duplicate removal message format: '[INFO] Removed X duplicate records.'"


def test_api_unauthorized():
    url = "http://127.0.0.1:8080/api/records?account_id=ACC-99281"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized when missing auth token, got {response.status_code}"


def test_api_authorized_and_data():
    url = "http://127.0.0.1:8080/api/records?account_id=ACC-99281"
    headers = {"Authorization": "Bearer secret-agent-token"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"

    try:
        response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    json_str = response.text.lower()
    assert "jonathan harker" in json_str, "Response JSON does not contain the extracted Customer Name 'Jonathan Harker'."
    assert "acc-99281" in json_str, "Response JSON does not contain the extracted Account ID 'ACC-99281'."
    assert "vampire bats in the server room" in json_str, "Response JSON does not contain the extracted Reported Issue 'vampire bats in the server room'."


def listener_pids(port=8080):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except OSError:
            pass
    return result


def kill_port():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def source_directories(preferred):
    found = []
    excluded = {".cache", "__pycache__", "node_modules", "pkg", ".git"}
    for root in ("/app", "/home/user"):
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in excluded]
            go_files = [f for f in files if f.endswith(".go") and not f.endswith("_test.go")]
            if not go_files:
                continue
            is_main = False
            for filename in go_files:
                path = os.path.join(current, filename)
                try:
                    with open(path, "r", errors="ignore") as f:
                        text = f.read(2_000_000)
                    if re.search(r"(?m)^\s*package\s+main\s*$", text):
                        is_main = True
                        break
                except OSError:
                    pass
            if is_main:
                found.append(current)

    found = list(dict.fromkeys(found))
    found.sort(key=lambda p: (0 if p in preferred else 1, -os.path.getmtime(p), p))
    return found[:20]


def build_go_program(directory, output):
    attempts = [os.environ.copy(), dict(os.environ, GO111MODULE="off")]
    errors = []
    for env in attempts:
        try:
            result = subprocess.run(
                ["go", "build", "-o", output, "."],
                cwd=directory,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=60,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(str(exc))
            continue
        if result.returncode == 0 and os.path.isfile(output):
            return True, ""
        errors.append(result.stdout[-2000:])
    return False, "\n".join(errors)


def authorized_get(account_id, timeout=2):
    return requests.get(
        "http://127.0.0.1:8080/api/records",
        params={"account_id": account_id},
        headers={"Authorization": "Bearer secret-agent-token"},
        timeout=timeout,
    )


def contains_record(response, account_id, names, issues):
    if response.status_code != 200:
        return False
    try:
        response.json()
    except ValueError:
        return False
    text = response.text.lower()
    return (
        account_id.lower() in text
        and any(name.lower() in text for name in names)
        and any(issue.lower() in text for issue in issues)
    )


def test_dynamic_csv_is_processed_by_go_artifact():
    token = uuid.uuid4().hex[:10]
    account_a1 = "DYN-A1-" + token
    account_a2 = "DYN-A2-" + token
    account_b1 = "DYN-B1-" + token
    account_b2 = "DYN-B2-" + token
    account_unique = "DYN-U-" + token
    account_blank = "DYN-E-" + token

    name_a1 = "Cedar " + token + " Stone"
    name_a2 = "Cedar " + token + " Ston"
    issue_a1 = "Printer, queue frozen " + token
    issue_a2 = "Printer, queue frozn " + token
    name_b1 = "Maple " + token + " Rivers"
    name_b2 = "Maple " + token + " River"
    issue_b1 = "Database sync stalled " + token
    issue_b2 = "Database sync staled " + token
    unique_name = "Quartz " + token + " Harbor"
    unique_issue = "Cooling alarm active " + token

    rows = [
        [name_a1, account_a1, issue_a1],
        [name_a2, account_a2, issue_a2],
        [name_b1, account_b1, issue_b1],
        [name_b2, account_b2, issue_b2],
        [unique_name, account_unique, unique_issue],
        ["", account_blank, ""],
    ]

    preferred = set()
    for pid in listener_pids():
        try:
            preferred.add(os.readlink(f"/proc/{pid}/cwd"))
        except OSError:
            pass

    candidates = source_directories(preferred)
    assert candidates, "No buildable Go service source was left in /app or /home/user"

    kill_port()
    csv_path = "/home/user/data/historical_records.csv"
    errors = []

    for index, directory in enumerate(candidates):
        kill_port()
        with open(csv_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Customer Name", "Account ID", "Reported Issue"])
            writer.writerows(rows)
        try:
            os.remove("/home/user/pipeline.log")
        except FileNotFoundError:
            pass

        binary = f"/tmp/submission_service_{index}"
        ok, build_error = build_go_program(directory, binary)
        if not ok:
            errors.append(f"{directory}: build failed: {build_error}")
            continue

        process = subprocess.Popen(
            [binary], cwd=directory, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        try:
            deadline = time.time() + 20
            while time.time() < deadline:
                try:
                    probe = authorized_get(account_unique, timeout=1)
                    if probe.status_code in (200, 404):
                        break
                except requests.RequestException:
                    pass
                if process.poll() is not None and not listener_pids():
                    break
                time.sleep(0.25)

            unauth = requests.get(
                "http://127.0.0.1:8080/api/records",
                params={"account_id": account_unique},
                timeout=3,
            )
            assert unauth.status_code == 401

            unique_response = authorized_get(account_unique, timeout=3)
            assert contains_record(unique_response, account_unique, [unique_name], [unique_issue])

            pair_a = [
                contains_record(authorized_get(account_a1), account_a1, [name_a1], [issue_a1]),
                contains_record(authorized_get(account_a2), account_a2, [name_a2], [issue_a2]),
            ]
            pair_b = [
                contains_record(authorized_get(account_b1), account_b1, [name_b1], [issue_b1]),
                contains_record(authorized_get(account_b2), account_b2, [name_b2], [issue_b2]),
            ]
            assert sum(pair_a) == 1, "First near-duplicate pair was not reduced to one record"
            assert sum(pair_b) == 1, "Second near-duplicate pair was not reduced to one record"

            incoming = authorized_get("ACC-99281", timeout=3)
            assert contains_record(
                incoming,
                "ACC-99281",
                ["Jonathan Harker"],
                ["vampire bats in the server room"],
            )

            with open("/home/user/pipeline.log") as f:
                log = f.read()
            assert re.search(r"\[INFO\] Removed 2 duplicate records\.", log), log
            return
        except Exception as exc:
            errors.append(f"{directory}: runtime verification failed: {exc}")
            kill_port()
            if process.poll() is None:
                process.kill()
                process.wait(timeout=3)

    pytest.fail("No submitted Go program processed the randomized CSV correctly:\n" + "\n".join(errors))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
