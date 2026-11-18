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
import json
import os
import re
import secrets
import sqlite3
import subprocess

import pytest
import requests

DB_PATH = "/home/user/research_data.db"
SCRIPT_PATH = "/home/user/export_summary.sh"
JSON_PATH = "/home/user/amazonas_summary.json"
TRANSCRIPT_PATH = "/home/user/transcript.txt"
SUMMARY_SQL = """
    SELECT t.tag_name, SUM(i.duration_seconds)
    FROM interviews i
    JOIN interview_tags it ON i.id = it.interview_id
    JOIN tags t ON it.tag_id = t.id
    WHERE i.location = 'Amazonas'
    GROUP BY t.tag_name
"""
BASELINE_SUMMARY = {"biodiversity": 3600}


def query_summary():
    with sqlite3.connect(DB_PATH) as conn:
        return {row[0]: row[1] for row in conn.execute(SUMMARY_SQL).fetchall()}


def load_summary_file():
    assert os.path.isfile(JSON_PATH), f"JSON file {JSON_PATH} missing."
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} is not valid JSON.")

    assert isinstance(data, list), "JSON should be a list of objects."
    assert all(isinstance(item, dict) for item in data), "Every JSON array item must be an object."
    assert all("tag" in item and "total_duration" in item for item in data), \
        "Every summary object must contain tag and total_duration."
    actual = {item.get("tag"): item.get("total_duration") for item in data if "tag" in item}
    assert len(data) == len(actual), "Summary contains duplicate or malformed tag entries."
    return data, actual


def run_export():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, \
        f"Export script failed with exit code {result.returncode}: {result.stderr}"
    assert os.path.isfile(JSON_PATH), "Export script did not create amazonas_summary.json."
    return load_summary_file()


def expected_transcript():
    for path in ("/app/whisper-cli", "/app/ggml-tiny.en.bin", "/app/pending_interview.wav"):
        assert os.path.isfile(path), f"Required transcription input {path} missing."
    result = subprocess.run(
        ["/app/whisper-cli", "-m", "/app/ggml-tiny.en.bin", "-f", "/app/pending_interview.wav"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"whisper-cli failed: {result.stderr}"
    timestamp = re.compile(r"^\s*\[[^\]]+\s*-->\s*[^\]]+\]\s*")
    raw_lines = []
    for line in result.stdout.splitlines():
        if timestamp.match(line):
            raw_lines.append(timestamp.sub("", line).strip())
    if not raw_lines:
        raw_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return "\n".join(raw_lines).strip()


def test_database_indexes():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index';")
    indexes = cursor.fetchall()
    indexed_tables = [idx[1] for idx in indexes]
    assert "interviews" in indexed_tables, "No index created on interviews table."
    assert "interview_tags" in indexed_tables, "No index created on interview_tags table."

    def indexed_column_sequences(table):
        sequences = []
        for row in conn.execute(f"PRAGMA index_list('{table}')"):
            index_name = row[1]
            columns = [r[2] for r in conn.execute(f"PRAGMA index_info('{index_name}')")]
            sequences.append(columns)
        return sequences

    interview_indexes = indexed_column_sequences("interviews")
    link_indexes = indexed_column_sequences("interview_tags")
    assert any(cols and cols[0] == "location" for cols in interview_indexes), \
        "interviews needs an index whose leading column is location."
    assert any(cols and cols[0] == "interview_id" for cols in link_indexes), \
        "interview_tags needs an index whose leading column is interview_id."

    cursor.execute("ANALYZE")
    plan = [row[3] for row in cursor.execute("EXPLAIN QUERY PLAN " + SUMMARY_SQL)]
    plan_text = "\n".join(plan)
    assert re.search(r"SEARCH\s+i\s+USING", plan_text, re.I), \
        f"Query plan does not use an index to filter interviews:\n{plan_text}"
    assert re.search(r"SEARCH\s+it\s+USING", plan_text, re.I), \
        f"Query plan does not use an index to join interview_tags:\n{plan_text}"
    conn.close()


def test_export_summary_script_and_json():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} missing."
    assert os.path.isfile(JSON_PATH), f"JSON file {JSON_PATH} missing."
    syntax = subprocess.run(
        ["/bin/bash", "-n", SCRIPT_PATH], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert syntax.returncode == 0, f"Export script is not valid Bash: {syntax.stderr}"

    assert query_summary() == BASELINE_SUMMARY, \
        "The original Amazonas database records were altered."

    _, actual_data = run_export()
    expected_data = query_summary()
    assert actual_data == expected_data, f"Expected summary {expected_data}, got {actual_data}"

    token = secrets.token_hex(8)
    tag_name = f"verification_{token}"
    duration = 10000 + secrets.randbelow(50000)
    with sqlite3.connect(DB_PATH) as conn:
        interview_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM interviews").fetchone()[0]
        tag_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM tags").fetchone()[0]
        conn.execute(
            "INSERT INTO interviews(id, date, location, duration_seconds, status) VALUES (?, ?, ?, ?, ?)",
            (interview_id, "2099-01-01", "Amazonas", duration, "done"),
        )
        conn.execute("INSERT INTO tags(id, tag_name) VALUES (?, ?)", (tag_id, tag_name))
        conn.execute(
            "INSERT INTO interview_tags(interview_id, tag_id) VALUES (?, ?)",
            (interview_id, tag_id),
        )

    expected_with_probe = dict(BASELINE_SUMMARY)
    expected_with_probe[tag_name] = duration
    try:
        _, probed_data = run_export()
        assert query_summary() == expected_with_probe, "Export script modified the database."
        assert probed_data == expected_with_probe, \
            f"Export script did not query the current database; expected {expected_with_probe}, got {probed_data}"
    finally:
        with sqlite3.connect(DB_PATH) as conn:
            conn.execute("DELETE FROM interview_tags WHERE interview_id = ?", (interview_id,))
            conn.execute("DELETE FROM interviews WHERE id = ?", (interview_id,))
            conn.execute("DELETE FROM tags WHERE id = ?", (tag_id,))
        _, restored_data = run_export()
        assert restored_data == BASELINE_SUMMARY, "Failed to restore the baseline summary after probing."


def test_transcript_content():
    assert os.path.isfile(TRANSCRIPT_PATH), f"Transcript file {TRANSCRIPT_PATH} missing."
    with open(TRANSCRIPT_PATH, "r") as f:
        content = f.read()

    lowered = content.lower()
    keywords = ["canopy density", "region", "survey"]
    for kw in keywords:
        assert kw in lowered, f"Expected keyword '{kw}' not found in transcript."

    expected = expected_transcript()
    assert content.strip() == expected, \
        f"Transcript is not the raw text produced for pending_interview.wav. Expected {expected!r}, got {content.strip()!r}"
    assert not re.search(r"\[\s*\d\d:\d\d:\d\d", content), \
        "Transcript should contain raw text without timestamp annotations."


def test_http_server_summary():
    try:
        resp = requests.get("http://127.0.0.1:8080/summary", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server on /summary: {e}")

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"
    assert "application/json" in resp.headers.get("Content-Type", ""), \
        "Expected Content-Type: application/json"

    with open(JSON_PATH, "r") as f:
        expected_json = json.load(f)
    try:
        actual_json = resp.json()
    except ValueError:
        pytest.fail("Response body is not valid JSON.")

    assert actual_json == expected_json, "HTTP response JSON does not match file."
    actual_map = {item["tag"]: item["total_duration"] for item in actual_json}
    assert actual_map == query_summary() == BASELINE_SUMMARY, \
        "HTTP summary does not represent the database's Amazonas aggregation."


def test_http_server_transcript():
    try:
        resp = requests.get("http://127.0.0.1:8080/transcript", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server on /transcript: {e}")

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"
    assert "text/plain" in resp.headers.get("Content-Type", ""), \
        "Expected Content-Type: text/plain"

    with open(TRANSCRIPT_PATH, "r") as f:
        expected_text = f.read()
    assert resp.text.strip() == expected_text.strip(), \
        "HTTP response text does not match transcript file."
    assert resp.text.strip() == expected_transcript(), \
        "HTTP transcript does not match the raw whisper-cli transcription."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
