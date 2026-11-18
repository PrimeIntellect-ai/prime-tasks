#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import csv
import random
import stat
import subprocess
import unicodedata
from datetime import datetime, timedelta

PIPELINE = "/home/user/pipeline.sh"
RAW_LOGS = "/home/user/raw_logs.jsonl"
SUMMARY = "/home/user/hourly_summary.csv"


def test_pipeline_script_exists_and_executable():
    assert os.path.exists(PIPELINE), f"Pipeline script not found at {PIPELINE}"
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is not a file"
    assert os.access(PIPELINE, os.X_OK), f"Pipeline script {PIPELINE} is not executable"


def _cleaning_script_path():
    with open(PIPELINE, "r", encoding="utf-8") as f:
        wrapper = f.read()

    candidates = []
    for line in wrapper.splitlines():
        code = line.split("#", 1)[0]
        if not re.search(r"(?:^|[\s/])python(?:3(?:\.\d+)*)?(?:\s|$)", code):
            continue
        for match in re.findall(r"(?<![A-Za-z0-9_])((?:/|\.{0,2}/)?[A-Za-z0-9_./-]+\.py)\b", code):
            path = os.path.expanduser(match)
            if not os.path.isabs(path):
                path = os.path.normpath(os.path.join("/home/user", path))
            candidates.append(path)

    assert candidates, "pipeline.sh must invoke a Python cleaning script (.py) with Python"
    existing = [p for p in candidates if os.path.isfile(p)]
    assert existing, f"Python script referenced by pipeline.sh does not exist: {candidates}"

    for path in existing:
        source = open(path, "r", encoding="utf-8").read()
        low = source.lower()
        has_ip = re.search(r"(?:['\"]ip['\"]|\bip\b)", low) is not None
        has_zero = re.search(r"(?:['\"]\.0['\"]|['\"]0['\"]|\b0\b)", low) is not None
        has_mask_operation = (
            (("split(" in low or "rsplit(" in low) and
             ("join(" in low or "[-1]" in low or ".0" in low))
            or (("re.sub(" in low or ".replace(" in low) and
                ("\\d" in source or ".0" in low))
            or ("ipaddress" in low and ("&" in source or ">>" in source or has_zero))
        )
        if has_ip and has_zero and has_mask_operation:
            return path

    raise AssertionError(
        "The Python script invoked by pipeline.sh does not implement IPv4 last-octet masking"
    )


def test_wrapper_invokes_python_cleaner_with_ip_masking():
    _cleaning_script_path()


def test_crontab_file_exists_and_correct():
    cron_path = "/home/user/my_cron"
    assert os.path.exists(cron_path), f"Crontab file not found at {cron_path}"

    with open(cron_path, "r") as f:
        lines = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]

    assert len(lines) >= 1, f"No valid cron jobs found in {cron_path}"

    found_valid_cron = False
    for line in lines:
        parts = line.split()
        if len(parts) >= 6:
            if parts[0] == "0" and parts[1] == "*" and parts[2] == "*" and parts[3] == "*" and parts[4] == "*":
                if "/home/user/pipeline.sh" in line:
                    found_valid_cron = True
                    break

    assert found_valid_cron, f"Could not find a valid hourly cron job for pipeline.sh in {cron_path}. Found lines: {lines}"


def _expected_rows(records):
    logs = []
    last_time = None
    for data in records:
        if data.get("time"):
            last_time = data["time"]
        assert last_time is not None, "Verifier fixture must begin with a valid timestamp"
        dt = datetime.strptime(last_time, "%Y-%m-%dT%H:%M:%SZ")
        hour_bin = dt.replace(minute=0, second=0, microsecond=0)
        norm_query = unicodedata.normalize("NFKC", data.get("query", ""))
        logs.append((hour_bin, len(norm_query), 1 if "bot" in data.get("ua", "").lower() else 0))

    min_hour = min(x[0] for x in logs)
    max_hour = max(x[0] for x in logs)
    bins = {}
    current = min_hour
    while current <= max_hour:
        bins[current] = {"total": 0, "bots": 0, "lengths": []}
        current += timedelta(hours=1)
    for hour, length, bot in logs:
        bins[hour]["total"] += 1
        bins[hour]["bots"] += bot
        bins[hour]["lengths"].append(length)

    rows = []
    current = min_hour
    while current <= max_hour:
        item = bins[current]
        avg = sum(item["lengths"]) / item["total"] if item["total"] else 0.0
        rows.append({
            "hour": current.strftime("%Y-%m-%d %H:00:00"),
            "total_requests": item["total"],
            "bot_requests": item["bots"],
            "avg_query_length": round(avg, 2),
        })
        current += timedelta(hours=1)
    return rows


def _write_records(records):
    with open(RAW_LOGS, "w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")


def _run_pipeline():
    return subprocess.run(
        [PIPELINE], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )


def _assert_summary(expected):
    assert os.path.isfile(SUMMARY), f"Pipeline did not create {SUMMARY}"
    with open(SUMMARY, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["hour", "total_requests", "bot_requests", "avg_query_length"], \
            f"CSV headers are incorrect: {reader.fieldnames}"
        actual = list(reader)
    assert len(actual) == len(expected), f"Expected {len(expected)} rows, got {len(actual)}"
    for i, (row, wanted) in enumerate(zip(actual, expected), 1):
        assert row["hour"] == wanted["hour"], f"Row {i} hour mismatch"
        assert int(row["total_requests"]) == wanted["total_requests"], f"Row {i} total_requests mismatch"
        assert int(row["bot_requests"]) == wanted["bot_requests"], f"Row {i} bot_requests mismatch"
        assert abs(float(row["avg_query_length"]) - wanted["avg_query_length"]) < 0.011, \
            f"Row {i} avg_query_length mismatch"


def _summary_matches(expected):
    try:
        _assert_summary(expected)
        return True
    except (AssertionError, OSError, ValueError, TypeError):
        return False


def test_pipeline_executes_reusable_python_cleaner():
    cleaner = _cleaning_script_path()
    with open(RAW_LOGS, "rb") as f:
        original_raw = f.read()
    cleaner_mode = stat.S_IMODE(os.stat(cleaner).st_mode)
    with open(cleaner, "rb") as f:
        original_cleaner = f.read()

    seed = random.SystemRandom().randrange(1, 10**9)
    rng = random.Random(seed)
    day = rng.randrange(2, 24)
    hour = rng.randrange(1, 17)
    n1, n2, n3 = rng.randrange(2, 10), rng.randrange(3, 12), rng.randrange(1, 8)
    base = datetime(2024, 2, day, hour, 0, 0)

    records = [
        {"time": (base + timedelta(minutes=7)).strftime("%Y-%m-%dT%H:%M:%SZ"),
         "ip": f"203.0.113.{rng.randrange(1,255)}", "query": "ﬁ" * n1, "ua": "Mozilla"},
        {"time": None, "ip": f"10.7.3.{rng.randrange(1,255)}", "query": "e\u0301" * n2, "ua": "MiXeDBoT/9"},
        {"time": (base + timedelta(hours=2, minutes=41)).strftime("%Y-%m-%dT%H:%M:%SZ"),
         "ip": f"198.51.100.{rng.randrange(1,255)}", "query": "Ａ" * n3, "ua": "curl"},
        {"time": None, "ip": f"172.20.8.{rng.randrange(1,255)}", "query": "多言語" * n1, "ua": "robot-agent"},
        {"time": (base + timedelta(hours=5, minutes=3)).strftime("%Y-%m-%dT%H:%M:%SZ"),
         "ip": f"192.0.2.{rng.randrange(1,255)}", "query": "x" * (n2 + n3), "ua": "Safari"},
    ]
    expected = _expected_rows(records)

    try:
        _write_records(records)
        if os.path.exists(SUMMARY):
            os.remove(SUMMARY)
        result = _run_pipeline()
        assert result.returncode == 0, f"pipeline.sh failed:\n{result.stdout}\n{result.stderr}"
        _assert_summary(expected)

        # The output must depend on the referenced Python cleaner, rather than
        # being produced directly by an unrelated shell command.
        with open(cleaner, "w", encoding="utf-8") as f:
            f.write("# verifier temporary no-op\n")
        os.chmod(cleaner, cleaner_mode)
        if os.path.exists(SUMMARY):
            os.remove(SUMMARY)
        noop_result = _run_pipeline()
        assert not (noop_result.returncode == 0 and _summary_matches(expected)), \
            "pipeline.sh still produced the correct summary when its Python cleaner was replaced by a no-op"
    finally:
        with open(cleaner, "wb") as f:
            f.write(original_cleaner)
        os.chmod(cleaner, cleaner_mode)
        with open(RAW_LOGS, "wb") as f:
            f.write(original_raw)
        if os.path.exists(SUMMARY):
            os.remove(SUMMARY)
        restored = _run_pipeline()
        assert restored.returncode == 0, \
            f"pipeline.sh failed on the restored input:\n{restored.stdout}\n{restored.stderr}"


def test_hourly_summary_csv():
    csv_path = "/home/user/hourly_summary.csv"
    assert os.path.exists(csv_path), f"Output CSV not found at {csv_path}"

    raw_logs_path = "/home/user/raw_logs.jsonl"
    assert os.path.exists(raw_logs_path), f"Raw logs file missing at {raw_logs_path}"

    logs = []
    last_time = None
    with open(raw_logs_path, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            if data.get("time"):
                last_time = data["time"]
            dt = datetime.strptime(last_time, "%Y-%m-%dT%H:%M:%SZ")
            hour_bin = dt.replace(minute=0, second=0, microsecond=0)
            query = data.get("query", "")
            norm_query = unicodedata.normalize("NFKC", query)
            q_len = len(norm_query)
            ua = data.get("ua", "")
            is_bot = 1 if "bot" in ua.lower() else 0
            logs.append({"hour": hour_bin, "q_len": q_len, "is_bot": is_bot})

    if not logs:
        return

    min_hour = min(log["hour"] for log in logs)
    max_hour = max(log["hour"] for log in logs)
    expected_data = {}
    curr_hour = min_hour
    while curr_hour <= max_hour:
        expected_data[curr_hour] = {"total": 0, "bots": 0, "q_lens": []}
        curr_hour += timedelta(hours=1)

    for log in logs:
        h = log["hour"]
        expected_data[h]["total"] += 1
        expected_data[h]["bots"] += log["is_bot"]
        expected_data[h]["q_lens"].append(log["q_len"])

    expected_rows = []
    curr_hour = min_hour
    while curr_hour <= max_hour:
        stats = expected_data[curr_hour]
        total = stats["total"]
        bots = stats["bots"]
        avg_len = sum(stats["q_lens"]) / total if total > 0 else 0.0
        expected_rows.append({
            "hour": curr_hour.strftime("%Y-%m-%d %H:00:00"),
            "total_requests": str(total),
            "bot_requests": str(bots),
            "avg_query_length": f"{avg_len:.2f}".rstrip('0').rstrip('.') if avg_len == 0.0 else str(round(avg_len, 2))
        })
        curr_hour += timedelta(hours=1)

    actual_rows = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["hour", "total_requests", "bot_requests", "avg_query_length"], \
            f"CSV headers are incorrect. Expected ['hour', 'total_requests', 'bot_requests', 'avg_query_length'], got {reader.fieldnames}"
        actual_rows.extend(reader)

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in CSV, got {len(actual_rows)}"
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual["hour"] == expected["hour"], f"Row {i+1} hour mismatch: expected {expected['hour']}, got {actual['hour']}"
        assert actual["total_requests"] == expected["total_requests"], f"Row {i+1} total_requests mismatch: expected {expected['total_requests']}, got {actual['total_requests']}"
        assert actual["bot_requests"] == expected["bot_requests"], f"Row {i+1} bot_requests mismatch: expected {expected['bot_requests']}, got {actual['bot_requests']}"
        actual_avg = float(actual["avg_query_length"])
        expected_avg = float(expected["avg_query_length"])
        assert abs(actual_avg - expected_avg) < 0.011, \
            f"Row {i+1} avg_query_length mismatch: expected {expected_avg}, got {actual_avg}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
