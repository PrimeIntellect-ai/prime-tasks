#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess

import pytest

HOME = "/home/user"
EXE = "/tmp/submission_program"
CSV_PATH = os.path.join(HOME, "bucket_stats.csv")
ALERT_PATH = os.path.join(HOME, "alerts.md")
INPUT_PATH = os.path.join(HOME, "input_logs.jsonl")
TEMPLATE_PATH = os.path.join(HOME, "alert_template.txt")


@pytest.fixture(scope="session", autouse=True)
def compile_cpp_program():
    sources = []
    for root, dirs, files in os.walk(HOME):
        for name in files:
            if name.endswith((".cpp", ".cc", ".cxx", ".C")):
                sources.append(os.path.join(root, name))

    assert sources, "No C++ source program was found under /home/user."
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-I", HOME, *sorted(sources), "-o", EXE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=90,
    )
    assert result.returncode == 0, "The C++ program did not compile:\n" + result.stdout
    assert os.path.isfile(EXE) and os.access(EXE, os.X_OK), "Compilation did not produce an executable."


def write_fixture(lines, template):
    with open(INPUT_PATH, "w", encoding="utf-8") as f:
        for line in lines:
            if isinstance(line, str):
                f.write(line + "\n")
            else:
                f.write(json.dumps(line, separators=(",", ":")) + "\n")
    with open(TEMPLATE_PATH, "w", encoding="utf-8") as f:
        f.write(template)
    for path in (CSV_PATH, ALERT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_program():
    result = subprocess.run(
        [EXE], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert result.returncode == 0, "The submitted program failed when executed:\n" + result.stdout


def derive_expected(input_path, template):
    valid = []
    with open(input_path, encoding="utf-8") as f:
        for order, line in enumerate(f):
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if not isinstance(obj, dict) or obj.get("svc") != "auth":
                continue
            status = obj.get("status")
            ts = obj.get("ts")
            rt = obj.get("rt")
            if type(status) is not int or not 200 <= status <= 599:
                continue
            if type(ts) is not int or type(rt) is not int:
                continue
            valid.append((ts, order, rt))

    valid.sort(key=lambda x: (x[0], x[1]))
    buckets = {}
    recent = []
    for ts, _, rt in valid:
        bucket = (ts // 60) * 60
        recent.append(rt)
        recent = recent[-3:]
        info = buckets.setdefault(bucket, {"values": [], "rolling": 0})
        info["values"].append(rt)
        info["rolling"] = sum(recent) // len(recent)

    rows = ["bucket_ts,count,bucket_avg,rolling_avg"]
    alerts = []
    for bucket in sorted(buckets):
        info = buckets[bucket]
        count = len(info["values"])
        avg = sum(info["values"]) // count
        rolling = info["rolling"]
        rows.append(f"{bucket},{count},{avg},{rolling}")
        if avg >= 500:
            block = template
            block = block.replace("{{ts}}", str(bucket))
            block = block.replace("{{avg}}", str(avg))
            block = block.replace("{{rolling}}", str(rolling))
            block = block.replace("{{count}}", str(count))
            alerts.append(block.rstrip("\n"))
    return rows, "\n\n".join(alerts)


def test_bucket_stats_csv_content():
    fixture = [
        {"ts": 1698141600, "svc": "auth", "status": 200, "rt": 100},
        {"ts": 1698141610, "svc": "web", "status": 200, "rt": 50},
        {"ts": 1698141630, "svc": "auth", "status": 500, "rt": 600},
        "invalid json line here",
        {"ts": 1698141659, "svc": "auth", "status": 200, "rt": 800},
        {"ts": 1698141660, "svc": "auth", "status": 200, "rt": 200},
        {"ts": 1698141665, "svc": "auth", "status": 401, "rt": 900},
        {"ts": 1698141700, "svc": "auth", "status": 200, "rt": 100},
        {"ts": 1698141705, "svc": "auth", "status": 600, "rt": 5000},
        {"ts": 1698141720, "svc": "auth", "status": 200, "rt": 700},
        {"ts": 1698141730, "svc": "auth", "status": 503, "rt": 1300},
    ]
    template = "## Alert for Bucket {{ts}}\n- Average Response Time: {{avg}}ms\n- Rolling Average at bucket end: {{rolling}}ms\n- Request Count: {{count}}\n"
    write_fixture(fixture, template)
    run_program()

    file_path = CSV_PATH
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."
    with open(file_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 4, "bucket_stats.csv does not contain enough rows."
    header = lines[0]
    assert header == "bucket_ts,count,bucket_avg,rolling_avg", f"Incorrect header in CSV: {header}"
    expected_rows = [
        "1698141600,3,500,500",
        "1698141660,3,400,400",
        "1698141720,2,1000,700",
    ]
    for i, expected_row in enumerate(expected_rows, start=1):
        assert lines[i] == expected_row, f"Row {i} in CSV mismatch. Expected '{expected_row}', got '{lines[i]}'"
    assert len(lines) == 4, "bucket_stats.csv contains unexpected extra rows."


def test_alerts_md_content():
    file_path = ALERT_PATH
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_alert_1 = """## Alert for Bucket 1698141600
- Average Response Time: 500ms
- Rolling Average at bucket end: 500ms
- Request Count: 3"""
    expected_alert_2 = """## Alert for Bucket 1698141720
- Average Response Time: 1000ms
- Rolling Average at bucket end: 700ms
- Request Count: 2"""
    assert expected_alert_1 in content, "First expected alert block is missing or malformed in alerts.md."
    assert expected_alert_2 in content, "Second expected alert block is missing or malformed in alerts.md."
    assert "1698141660" not in content, "Alert for Bucket 1698141660 should not be generated (avg < 500)."
    assert content == expected_alert_1 + "\n\n" + expected_alert_2, "alerts.md contains missing, malformed, or extra alert content."


def test_program_processes_unseen_input_and_template():
    rng = random.SystemRandom()
    base = ((1800000000 + rng.randrange(1000, 900000) * 60) // 60) * 60
    d = rng.randrange(1, 50)
    marker = f"fixture-{rng.randrange(10**8, 10**9)}"
    fixture = [
        {"ts": base + 1, "svc": "auth", "status": 200, "rt": 100 + d},
        {"ts": base + 8, "svc": "other", "status": 200, "rt": 9999},
        "{ definitely malformed json",
        {"ts": base + 40, "svc": "auth", "status": 599, "rt": 900 + d},
        {"ts": base + 60, "svc": "auth", "status": 200, "rt": 200 + d},
        {"ts": base + 65, "svc": "auth", "status": 199, "rt": 8000},
        {"ts": base + 90, "svc": "auth", "status": 500, "rt": 250 + d},
        {"ts": base + 120, "svc": "auth", "status": 200.0, "rt": 7000},
        {"ts": base + 125, "svc": "auth", "status": True, "rt": 7000},
        {"ts": base + 180, "svc": "auth", "status": 201, "rt": 700 + d},
        {"ts": base + 190, "svc": "auth", "status": 503, "rt": 800 + d},
        {"ts": base + 200, "svc": "auth", "status": 401, "rt": 100 + d},
        {"ts": str(base + 205), "svc": "auth", "status": 200, "rt": 9999},
        {"ts": base + 240, "svc": "auth", "status": 200, "rt": 300 + d},
        {"ts": base + 245, "svc": "auth", "status": 600, "rt": 9999},
        {"ts": base + 250, "svc": "auth", "status": 200, "rt": "400"},
        {"ts": base + 251, "svc": "auth", "rt": 5000},
    ]
    template = f"### {marker} / {{ts}}\nAVG={{avg}} ROLL={{rolling}} COUNT={{count}} TS={{ts}}\n"
    template = template.replace("{ts}", "{{ts}}").replace("{avg}", "{{avg}}").replace("{rolling}", "{{rolling}}").replace("{count}", "{{count}}")
    write_fixture(fixture, template)
    expected_rows, expected_alerts = derive_expected(INPUT_PATH, template)
    run_program()

    assert os.path.isfile(CSV_PATH), "Program did not create bucket_stats.csv for unseen input."
    with open(CSV_PATH, encoding="utf-8") as f:
        actual_rows = [line.strip() for line in f if line.strip()]
    assert actual_rows == expected_rows, f"CSV output for unseen input is incorrect.\nExpected: {expected_rows}\nActual: {actual_rows}"

    assert os.path.isfile(ALERT_PATH), "Program did not create alerts.md for unseen input."
    with open(ALERT_PATH, encoding="utf-8") as f:
        actual_alerts = f.read().strip()
    assert actual_alerts == expected_alerts.strip(), "Alert output for unseen input/template is incorrect or contains extra blocks."
    assert marker in actual_alerts, "The program did not use the supplied alert template."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
