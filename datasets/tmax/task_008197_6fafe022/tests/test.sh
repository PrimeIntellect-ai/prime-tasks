#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import pytest
import pwd
import re
import secrets
import shutil
import signal
import subprocess
import time
from collections import Counter

RAW_FILE = "/home/user/raw_data/transactions.csv"
SCRIPT_FILE = "/home/user/etl_pipeline.sh"
OUTPUT_DIR = "/home/user/etl_output"
MASKED_FILE = os.path.join(OUTPUT_DIR, "masked.csv")
ROLLING_FILE = os.path.join(OUTPUT_DIR, "rolling.csv")
SUMMARY_FILE = os.path.join(OUTPUT_DIR, "summary.json")
EXPECTED_RAW_DATA = []


def build_input():
    global EXPECTED_RAW_DATA
    categories = ["Retail", "Tech", "Food", "Travel", "Services"]
    base = 1700000000 + secrets.randbelow(1000000)
    salt = secrets.token_hex(5)
    rows = []
    for i in range(4000):
        cents = 1 + secrets.randbelow(500000)
        rows.append({
            "timestamp": str(base + i * 7),
            "email": f"u{i}_{salt}@domain{(i % 17) + 1}.example",
            "ip": f"10.{(i // 251) % 250}.{i % 251}.{1 + (i * 37) % 254}",
            "amount": f"{cents / 100:.2f}",
            "category": categories[i % len(categories)],
        })
    EXPECTED_RAW_DATA = rows
    os.makedirs(os.path.dirname(RAW_FILE), exist_ok=True)
    with open(RAW_FILE, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["timestamp", "email", "ip", "amount", "category"])
        writer.writeheader()
        writer.writerows(rows)


def session_processes(session_id, main_pid):
    processes = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            with open(f"/proc/{pid}/stat", "r") as f:
                stat = f.read()
            tail = stat[stat.rfind(")") + 2:].split()
            state = tail[0]
            sid = int(tail[3])
            if sid != session_id or state == "Z" or pid == main_pid:
                continue
            with open(f"/proc/{pid}/comm", "r") as f:
                comm = f.read().strip()
            processes.append((pid, comm))
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError, IndexError):
            pass
    return processes


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_FILE), f"Master script missing at {SCRIPT_FILE}"
    assert os.access(SCRIPT_FILE, os.X_OK), f"Master script {SCRIPT_FILE} is not executable."

    with open(SCRIPT_FILE, "r", errors="replace") as f:
        script_text = f.read()

    non_comment_text = "\n".join(
        line for line in script_text.splitlines() if not line.lstrip().startswith("#")
    )
    forbidden = re.compile(r"\b(?:python(?:[0-9.]*)?|node(?:js)?)\b", re.IGNORECASE)
    assert not forbidden.search(non_comment_text), "The ETL script must not use Python or Node.js"

    has_parallel_construct = (
        (re.search(r"\bxargs\b", non_comment_text) and re.search(r"(?:^|\s)(?:-P|--max-procs(?:=|\s))", non_comment_text))
        or re.search(r"(?:^|[;|&\s])parallel(?:\s|$)", non_comment_text)
        or re.search(r"(?<![>&])&(?![>&\d])", non_comment_text)
        or "<(" in non_comment_text
        or re.search(r"\bcoproc\b", non_comment_text)
    )
    assert has_parallel_construct, "No row-parallel processing construct was found in the ETL script"

    build_input()
    shutil.rmtree(OUTPUT_DIR, ignore_errors=True)

    user = pwd.getpwnam("user")
    env = os.environ.copy()
    env.update({"HOME": user.pw_dir, "USER": user.pw_name, "LOGNAME": user.pw_name})

    def demote_and_start_session():
        os.setsid()
        os.initgroups(user.pw_name, user.pw_gid)
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    proc = subprocess.Popen(
        [SCRIPT_FILE],
        cwd="/home/user",
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=demote_and_start_session,
    )

    deadline = time.monotonic() + 180
    max_workers = 0
    max_same_worker = 0
    forbidden_runtime = set()
    while proc.poll() is None:
        workers = session_processes(proc.pid, proc.pid)
        max_workers = max(max_workers, len(workers))
        counts = Counter(comm for _, comm in workers)
        if counts:
            max_same_worker = max(max_same_worker, max(counts.values()))
        for _, comm in workers:
            if re.fullmatch(r"python(?:[0-9.]*)?|node(?:js)?", comm, re.IGNORECASE):
                forbidden_runtime.add(comm)
        if time.monotonic() > deadline:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait()
            pytest.fail("ETL script timed out")
        time.sleep(0.001)

    returncode = proc.wait()
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

    assert returncode == 0, f"ETL script exited with status {returncode}"
    assert not forbidden_runtime, f"ETL script used a forbidden runtime: {sorted(forbidden_runtime)}"
    assert max_workers >= 4, f"Observed only {max_workers} concurrent child processes; at least 4 are required"
    assert max_same_worker >= 4, "Did not observe at least four concurrent row-processing workers"
    yield


def read_raw_data():
    return [dict(row) for row in EXPECTED_RAW_DATA]


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_FILE), f"Master script missing at {SCRIPT_FILE}"
    assert os.access(SCRIPT_FILE, os.X_OK), f"Master script {SCRIPT_FILE} is not executable."


def test_output_directory_exists():
    assert os.path.isdir(OUTPUT_DIR), f"Output directory missing at {OUTPUT_DIR}"


def test_masked_csv():
    assert os.path.isfile(MASKED_FILE), f"Masked file missing at {MASKED_FILE}"

    raw_data = read_raw_data()
    raw_data.sort(key=lambda x: int(x["timestamp"]))

    with open(MASKED_FILE, "r") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["timestamp", "email", "ip", "amount", "category"], "Incorrect header in masked.csv"

        rows = list(reader)
        assert len(rows) == len(raw_data), f"Expected {len(raw_data)} rows in masked.csv, got {len(rows)}"

        for i, (actual_row, expected_dict) in enumerate(zip(rows, raw_data)):
            ts, email, ip, amt, cat = actual_row
            assert ts == expected_dict["timestamp"], f"Row {i+1}: Timestamp mismatch"
            assert amt == expected_dict["amount"], f"Row {i+1}: Amount mismatch"
            assert cat == expected_dict["category"], f"Row {i+1}: Category mismatch"

            orig_email = expected_dict["email"]
            orig_user, orig_domain = orig_email.split("@")
            expected_email = f"{orig_user[0]}***@{orig_domain}"
            assert email == expected_email, f"Row {i+1}: Email masking incorrect. Expected {expected_email}, got {email}"

            orig_ip = expected_dict["ip"]
            ip_parts = orig_ip.split(".")
            expected_ip = f"{ip_parts[0]}.{ip_parts[1]}.{ip_parts[2]}.0"
            assert ip == expected_ip, f"Row {i+1}: IP masking incorrect. Expected {expected_ip}, got {ip}"


def test_rolling_csv():
    assert os.path.isfile(ROLLING_FILE), f"Rolling file missing at {ROLLING_FILE}"

    raw_data = read_raw_data()
    raw_data.sort(key=lambda x: int(x["timestamp"]))

    category_history = {}
    expected_rolling = []
    for row in raw_data:
        cat = row["category"]
        amt = float(row["amount"])
        if cat not in category_history:
            category_history[cat] = []
        category_history[cat].append(amt)
        window = category_history[cat][-3:]
        rolling_avg = sum(window) / len(window)
        expected_rolling.append((row["timestamp"], cat, f"{rolling_avg:.2f}"))

    with open(ROLLING_FILE, "r") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["timestamp", "category", "rolling_avg"], "Incorrect header in rolling.csv"
        rows = list(reader)
        assert len(rows) == len(expected_rolling), f"Expected {len(expected_rolling)} rows in rolling.csv, got {len(rows)}"
        for i, (actual, expected) in enumerate(zip(rows, expected_rolling)):
            assert tuple(actual) == expected, f"Row {i+1}: Rolling average mismatch. Expected {expected}, got {tuple(actual)}"


def test_summary_json():
    assert os.path.isfile(SUMMARY_FILE), f"Summary file missing at {SUMMARY_FILE}"

    raw_data = read_raw_data()
    category_stats = {}
    for row in raw_data:
        cat = row["category"]
        amt = float(row["amount"])
        if cat not in category_stats:
            category_stats[cat] = []
        category_stats[cat].append(amt)

    with open(SUMMARY_FILE, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("summary.json contains invalid JSON")

    for cat, amounts in category_stats.items():
        assert cat in summary, f"Category '{cat}' missing from summary.json"
        expected_total = sum(amounts)
        expected_avg = expected_total / len(amounts)
        actual_total = float(summary[cat]["total"])
        actual_avg = float(summary[cat]["avg"])
        assert abs(actual_total - expected_total) < 0.01, f"Total for {cat} mismatch. Expected {expected_total:.2f}, got {actual_total}"
        assert abs(actual_avg - expected_avg) < 0.01, f"Average for {cat} mismatch. Expected {expected_avg:.2f}, got {actual_avg}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
