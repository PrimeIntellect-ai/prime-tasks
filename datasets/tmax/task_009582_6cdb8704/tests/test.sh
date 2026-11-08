#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile

import pytest

SUMMARY_PATH = "/home/user/output/summary.json"
LOG_PATH = "/home/user/output/pipeline.log"
DATA_DIR = Path("/home/user/data/feedback")
OUTPUT_DIR = Path("/home/user/output")
HOME_DIR = Path("/home/user")


def test_summary_exists():
    assert os.path.isfile(SUMMARY_PATH), f"Summary file {SUMMARY_PATH} is missing. Make sure the script creates it."


def test_summary_content():
    with open(SUMMARY_PATH, 'r') as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {SUMMARY_PATH} is not valid JSON.")

    expected_summary = {
        "electronics": 3.67,
        "home": 3.5,
        "garden": 3.0,
        "toys": 4.5
    }

    for category, expected_val in expected_summary.items():
        assert category in summary, f"Category '{category}' missing from summary."
        val = summary[category]
        assert isinstance(val, (int, float)), f"Value for '{category}' should be a number, got {type(val).__name__}."
        assert math.isclose(val, expected_val, abs_tol=0.01), \
            f"Mismatch in {category}: expected ~{expected_val}, got {val}"

    extra_keys = set(summary.keys()) - set(expected_summary.keys())
    assert not extra_keys, f"Found unexpected categories in summary: {extra_keys}"


def test_pipeline_log_exists():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing. Ensure the pipeline creates it."


def test_pipeline_log_content():
    with open(LOG_PATH, 'r') as f:
        log_lines = [line.strip() for line in f if line.strip()]

    expected_logs = [
        "[INFO] Processed batch1.csv: 4 records",
        "[INFO] Processed batch2.json: 3 records",
        "[INFO] Processed batch3.csv: 2 records"
    ]

    assert len(log_lines) == len(expected_logs), \
        f"Expected {len(expected_logs)} log entries, but got {len(log_lines)}."

    assert log_lines == expected_logs, \
        f"Log file contents do not match expected output or are not sorted properly.\nExpected: {expected_logs}\nGot: {log_lines}"


def script_command(path):
    suffix = path.suffix.lower()
    if suffix == ".py":
        return ["python3", str(path)]
    if suffix == ".js":
        return ["node", str(path)]
    if suffix in (".sh", ".bash"):
        return ["bash", str(path)]

    try:
        first_line = path.open("rb").readline(256).decode("utf-8", "ignore").lower()
    except OSError:
        return None
    if not first_line.startswith("#!"):
        return None
    if "python" in first_line:
        return ["python3", str(path)]
    if "node" in first_line:
        return ["node", str(path)]
    if any(shell in first_line for shell in ("bash", "/sh", "zsh")):
        return ["bash", str(path)]
    return None


def find_pipeline_candidates():
    ignored_dirs = {".cache", ".local", ".venv", "venv", "node_modules", "__pycache__"}
    candidates = []
    for root, dirs, files in os.walk(HOME_DIR):
        dirs[:] = [d for d in dirs if d not in ignored_dirs]
        for filename in files:
            path = Path(root) / filename
            if str(path) in (SUMMARY_PATH, LOG_PATH):
                continue
            command = script_command(path)
            if command is not None:
                name = path.name.lower()
                priority = 0 if any(word in name for word in ("pipeline", "process", "feedback", "main", "run")) else 1
                candidates.append((priority, str(path), command))
    candidates.sort(key=lambda item: (item[0], item[1]))
    return [(Path(path), command) for _, path, command in candidates]


def read_dynamic_result(expected_summary, expected_logs):
    if not Path(SUMMARY_PATH).is_file() or not Path(LOG_PATH).is_file():
        return False, "summary.json or pipeline.log was not created"

    try:
        with open(SUMMARY_PATH, "r") as f:
            summary = json.load(f)
    except Exception as exc:
        return False, f"summary.json is invalid: {exc}"

    if not isinstance(summary, dict) or set(summary) != set(expected_summary):
        return False, f"unexpected summary keys/content: {summary!r}"
    for category, expected in expected_summary.items():
        value = summary.get(category)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return False, f"non-numeric value for {category}: {value!r}"
        if not math.isclose(value, expected, abs_tol=1e-9):
            return False, f"wrong average for {category}: expected {expected}, got {value}"

    with open(LOG_PATH, "r") as f:
        logs = [line.strip() for line in f if line.strip()]
    if logs != expected_logs:
        return False, f"wrong dynamic log: expected {expected_logs!r}, got {logs!r}"
    return True, "ok"


def test_pipeline_script_executes_and_handles_unseen_multiline_data():
    candidates = find_pipeline_candidates()
    assert candidates, "No Python, Node.js, or shell pipeline script was found under /home/user."

    token = secrets.token_hex(5)
    cat_a = f"mixed_{token}"
    cat_b = f"service_{token}"
    cat_c = f"other_{token}"
    json_name = f"a_{token}.json"
    csv_name_2 = f"m_{token}.csv"
    csv_name_1 = f"z_{token}.csv"

    records_by_file = {
        csv_name_1: [
            {"id": 101, "product_category": cat_a, "rating": 5, "feedback_text": "first line\nsecond line\nthird line"},
            {"id": 102, "product_category": cat_b, "rating": 1, "feedback_text": "contains, a comma"},
        ],
        json_name: [
            {"id": 103, "product_category": cat_a, "rating": 2, "feedback_text": "from json"},
            {"id": 104, "product_category": cat_b, "rating": 4, "feedback_text": "also json"},
        ],
        csv_name_2: [
            {"id": 105, "product_category": cat_a, "rating": 4, "feedback_text": "another\nmultiline value"},
            {"id": 106, "product_category": cat_c, "rating": 3, "feedback_text": "plain"},
        ],
    }

    totals = {}
    for records in records_by_file.values():
        for record in records:
            totals.setdefault(record["product_category"], []).append(record["rating"])
    expected_summary = {
        category: round(sum(ratings) / len(ratings), 2)
        for category, ratings in totals.items()
    }
    expected_logs = [
        f"[INFO] Processed {name}: {len(records_by_file[name])} records"
        for name in sorted(records_by_file)
    ]

    with tempfile.TemporaryDirectory() as temporary:
        backup_data = Path(temporary) / "feedback"
        backup_output = Path(temporary) / "output"
        shutil.copytree(DATA_DIR, backup_data)
        shutil.copytree(OUTPUT_DIR, backup_output)

        diagnostics = []
        try:
            for path in list(DATA_DIR.rglob("*")):
                if path.is_file() and path.suffix.lower() in (".csv", ".json"):
                    path.unlink()

            for name, records in records_by_file.items():
                destination = DATA_DIR / name
                if destination.suffix == ".json":
                    with destination.open("w", encoding="utf-8") as f:
                        json.dump(records, f)
                else:
                    with destination.open("w", newline="", encoding="utf-8") as f:
                        writer = csv.DictWriter(f, fieldnames=["id", "product_category", "rating", "feedback_text"])
                        writer.writeheader()
                        writer.writerows(records)
                os.chmod(destination, 0o644)

            for candidate, command in candidates:
                OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
                for artifact in (Path(SUMMARY_PATH), Path(LOG_PATH)):
                    if artifact.exists():
                        artifact.unlink()
                try:
                    result = subprocess.run(
                        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", *command],
                        cwd="/home/user",
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        timeout=20,
                    )
                    ok, reason = read_dynamic_result(expected_summary, expected_logs)
                    if result.returncode == 0 and ok:
                        return
                    diagnostics.append(f"{candidate}: exit={result.returncode}; {reason}; output={result.stdout[-500:]!r}")
                except (subprocess.SubprocessError, OSError) as exc:
                    diagnostics.append(f"{candidate}: execution failed: {exc}")

            pytest.fail("No discovered pipeline script produced correct results for unseen mixed-format data. " + " | ".join(diagnostics[-8:]))
        finally:
            if DATA_DIR.exists():
                shutil.rmtree(DATA_DIR)
            shutil.copytree(backup_data, DATA_DIR)
            if OUTPUT_DIR.exists():
                shutil.rmtree(OUTPUT_DIR)
            shutil.copytree(backup_output, OUTPUT_DIR)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
