#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import sqlite3
import subprocess
import textwrap

import pytest

WORKSPACE = "/home/user/legacy_aggregator"
REPORT_PATH = "/home/user/debug_report.json"
INPUT_CSV = os.path.join(WORKSPACE, "input_data.csv")
CRASH_DMP = os.path.join(WORKSPACE, "crash.dmp")
DB_PATH = os.path.join(WORKSPACE, "results.db")
REQ_PATH = os.path.join(WORKSPACE, "requirements.txt")
MAIN_PATH = os.path.join(WORKSPACE, "main.py")
VENV_PATH = os.path.join(WORKSPACE, "venv")
VENV_PYTHON = os.path.join(VENV_PATH, "bin", "python")

ORIGINAL_BUGGY_MAIN = '''import pandas as pd
import threading
import sqlite3
from concurrent.futures import ThreadPoolExecutor

stats = {'total_score': 0, 'record_count': 0}

def process_chunk(chunk):
    global stats
    local_sum = chunk['score'].sum()
    local_count = len(chunk)

    # Bug: Race condition updating global state without a lock
    # A time.sleep(0.001) could be added to force the race condition if needed
    stats['total_score'] += local_sum
    stats['record_count'] += local_count

def main():
    df = pd.read_csv('input_data.csv')
    chunks = [df[i:i+100] for i in range(0, len(df), 100)]

    with ThreadPoolExecutor(max_workers=10) as executor:
        executor.map(process_chunk, chunks)

    conn = sqlite3.connect('results.db')
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS aggregate (total_score INTEGER, record_count INTEGER)')
    c.execute('DELETE FROM aggregate')
    c.execute('INSERT INTO aggregate (total_score, record_count) VALUES (?, ?)', 
              (int(stats['total_score']), int(stats['record_count'])))
    conn.commit()
    conn.close()
    print("Processing complete.")

if __name__ == '__main__':
    main()
'''


def read_input_totals():
    total = 0
    count = 0
    with open(INPUT_CSV, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["user_id", "score"]
        for row in reader:
            total += int(row["score"])
            count += 1
    return total, count


def get_expected_token():
    with open(CRASH_DMP, "rb") as f:
        match = re.search(rb"AUTH_TOKEN=([a-zA-Z0-9]{16})", f.read())
    return match.group(1).decode("ascii") if match else ""


def pinned_requirements():
    pins = {}
    with open(REQ_PATH) as f:
        for raw_line in f:
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            match = re.fullmatch(r"([A-Za-z0-9_.-]+)\s*==\s*([^\s;]+)", line)
            if match:
                pins[match.group(1).lower().replace("_", "-")] = match.group(2)
    return pins


def query_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT total_score, record_count FROM aggregate"
        ).fetchall()
    finally:
        conn.close()
    assert len(rows) == 1, "aggregate must contain exactly one result row"
    return rows[0]


def run_main_with_race_stress():
    # Opcode-level yielding makes the starter's unprotected read/modify/write
    # reliably interleave, while correct lock-based or reduction-based fixes work.
    runner = textwrap.dedent(f'''
        import os
        import runpy
        import sys
        import threading
        import time

        target = {MAIN_PATH!r}
        def trace(frame, event, arg):
            if frame.f_code.co_filename == target and frame.f_code.co_name == "process_chunk":
                frame.f_trace_opcodes = True
                if event == "opcode":
                    time.sleep(0.0001)
            return trace

        threading.settrace(trace)
        sys.setswitchinterval(1e-6)
        runpy.run_path(target, run_name="__main__")
    ''')
    subprocess.run(
        [VENV_PYTHON, "-c", runner],
        cwd=WORKSPACE,
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_input_data_was_not_modified():
    with open(INPUT_CSV, newline="") as f:
        rows = list(csv.reader(f))
    assert rows[0] == ["user_id", "score"]
    assert len(rows) == 10001
    for expected_id, row in enumerate(rows[1:], 1):
        assert row == [str(expected_id), "10"], "input_data.csv was modified"


def test_report_exists_and_valid():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH) as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {REPORT_PATH} is not valid JSON.")

    expected_score, _ = read_input_totals()
    assert "extracted_token" in report, "Missing 'extracted_token' in report."
    assert report["extracted_token"] == get_expected_token(), "Incorrect extracted_token."
    assert "correct_total_score" in report, "Missing 'correct_total_score' in report."
    assert report["correct_total_score"] == expected_score, "Incorrect correct_total_score."
    assert "fixed_urllib3_version" in report, "Missing 'fixed_urllib3_version' in report."
    assert isinstance(report["fixed_urllib3_version"], str), "fixed_urllib3_version must be a string."


def test_database_results():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    expected_score, expected_count = read_input_totals()
    assert query_database() == (expected_score, expected_count)


def test_requirements_were_fixed_and_installed():
    assert os.path.isfile(REQ_PATH), "requirements.txt is missing"
    pins = pinned_requirements()
    assert pins.get("requests") == "2.31.0", "requests must remain pinned to 2.31.0"
    assert "urllib3" in pins, "urllib3 must have an exact version pin"
    assert pins["urllib3"] != "1.25.11", "the original urllib3 pin was not fixed"
    assert pins.get("pandas") == "2.0.3", "the required pandas pin is missing"

    assert os.path.isdir(VENV_PATH), f"Virtual environment {VENV_PATH} does not exist."
    assert os.path.isfile(os.path.join(VENV_PATH, "pyvenv.cfg")), "venv is not a real virtual environment"
    assert os.path.isfile(VENV_PYTHON) and os.access(VENV_PYTHON, os.X_OK), "venv Python is missing"

    code = '''
import json, os, sys
import pandas, requests, urllib3
print(json.dumps({
    "prefix": os.path.realpath(sys.prefix),
    "pandas": pandas.__version__,
    "requests": requests.__version__,
    "urllib3": urllib3.__version__,
}))
'''
    proc = subprocess.run(
        [VENV_PYTHON, "-c", code], check=True, timeout=30,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    installed = json.loads(proc.stdout.strip().splitlines()[-1])
    assert installed["prefix"] == os.path.realpath(VENV_PATH)
    assert installed["pandas"] == pins["pandas"]
    assert installed["requests"] == pins["requests"]
    assert installed["urllib3"] == pins["urllib3"]

    subprocess.run(
        [VENV_PYTHON, "-m", "pip", "check"], check=True, timeout=30,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    with open(REPORT_PATH) as f:
        report = json.load(f)
    assert report["fixed_urllib3_version"] == pins["urllib3"]


def test_fixed_main_executes_correctly_under_concurrency():
    assert os.path.isfile(MAIN_PATH), "main.py is missing"
    with open(MAIN_PATH) as f:
        source = f.read()
    assert source != ORIGINAL_BUGGY_MAIN, "main.py is still the original buggy implementation"

    with open(INPUT_CSV, "rb") as f:
        original_input = f.read()

    rng = random.SystemRandom()
    try:
        # Use verifier-generated data so a prebuilt database or hard-coded answer
        # cannot satisfy the execution check.
        for size in (3000, 3700):
            scores = [rng.randint(-5000, 5000) for _ in range(size)]
            with open(INPUT_CSV, "w", newline="") as f:
                writer = csv.writer(f, lineterminator="\n")
                writer.writerow(["user_id", "score"])
                writer.writerows((i + 1, score) for i, score in enumerate(scores))
            if os.path.exists(DB_PATH):
                os.remove(DB_PATH)
            run_main_with_race_stress()
            assert query_database() == (sum(scores), size)
    finally:
        with open(INPUT_CSV, "wb") as f:
            f.write(original_input)
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        run_main_with_race_stress()

    expected_score, expected_count = read_input_totals()
    assert query_database() == (expected_score, expected_count)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
