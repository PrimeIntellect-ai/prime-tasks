#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import shutil
import sqlite3
import stat
import subprocess
import unicodedata

import pytest

HOME = "/home/user"
RAW = os.path.join(HOME, "raw_subs.csv")
PIPELINE = os.path.join(HOME, "pipeline.go")
CLEAN = os.path.join(HOME, "clean_subs.csv")
DB = os.path.join(HOME, "subs.db")
SCORE_FILE = os.path.join(HOME, "final_score.txt")
EVAL = "/app/eval_lqs"
RAW_BACKUP = "/tmp/raw_subs.verifier_backup.csv"


def run_evaluator():
    assert os.path.exists(EVAL), f"Evaluator binary missing: {EVAL}"
    assert os.access(EVAL, os.X_OK), f"Evaluator binary not executable: {EVAL}"
    try:
        result = subprocess.run(
            [EVAL, DB], capture_output=True, text=True, check=True, timeout=60
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Evaluator execution failed with exit code {e.returncode}. stderr: {e.stderr}"
        )
    output = result.stdout.strip()
    try:
        score = float(output)
    except ValueError:
        pytest.fail(f"Evaluator output could not be parsed as a float. Output was: {output}")
    assert math.isfinite(score), f"Evaluator returned a non-finite score: {output}"
    return score


def normalize_text(value):
    value = re.sub(r"<[^>]*>", "", value)
    value = "".join(ch for ch in value if not unicodedata.category(ch).startswith("P"))
    return " ".join(value.lower().split())


def round_nearest_positive(numerator, denominator):
    # Timestamps are nonnegative; this is Go math.Round behavior at exact halves.
    return (2 * numerator + denominator) // (2 * denominator)


def expected_rows(raw_path):
    with open(raw_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "start_ms", "end_ms", "raw_text"]
        rows = list(reader)

    assert rows, "Raw input contains no subtitle rows"
    result = []
    for field in ("start_ms", "end_ms"):
        valid = [i for i, row in enumerate(rows) if int(row[field]) != -1]
        assert valid, f"No valid anchors for {field}"
        for i, row in enumerate(rows):
            if int(row[field]) != -1:
                continue
            before = max((j for j in valid if j < i), default=None)
            after = min((j for j in valid if j > i), default=None)
            assert before is not None and after is not None, (
                f"Missing {field} at row {i + 1} lacks interpolation anchors"
            )
            left = int(rows[before][field])
            right = int(rows[after][field])
            span = after - before
            offset = i - before
            numerator = left * (span - offset) + right * offset
            row[field] = str(round_nearest_positive(numerator, span))

    for row in rows:
        result.append((
            int(row["id"]),
            int(row["start_ms"]),
            int(row["end_ms"]),
            normalize_text(row["raw_text"]),
        ))
    return result


def assert_outputs_match(raw_path, required_count=None):
    expected = expected_rows(raw_path)
    if required_count is not None:
        assert len(expected) == required_count

    assert os.path.exists(CLEAN), f"Cleaned CSV missing: {CLEAN}"
    assert os.path.isfile(CLEAN), f"Expected a file at {CLEAN}"
    with open(CLEAN, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        clean_rows = list(reader)
    assert clean_rows, "Cleaned CSV is empty"
    assert clean_rows[0] == ["id", "start_ms", "end_ms", "text"], (
        f"Unexpected cleaned CSV header: {clean_rows[0]}"
    )
    actual_csv = []
    for line_number, row in enumerate(clean_rows[1:], start=2):
        assert len(row) == 4, f"Cleaned CSV line {line_number} has {len(row)} fields"
        try:
            actual_csv.append((int(row[0]), int(row[1]), int(row[2]), row[3]))
        except ValueError as e:
            pytest.fail(f"Invalid integer in cleaned CSV line {line_number}: {e}")
    assert actual_csv == expected, "Cleaned CSV does not match the repaired raw input"

    assert os.path.exists(DB), f"Database file missing: {DB}"
    assert os.path.isfile(DB), f"Expected a file at {DB}"
    assert os.path.getsize(DB) > 0, f"Database file is empty: {DB}"
    conn = sqlite3.connect(DB)
    try:
        schema = conn.execute("PRAGMA table_info(subtitles)").fetchall()
        assert [(r[1], r[2].upper(), r[5]) for r in schema] == [
            ("id", "INTEGER", 1),
            ("start_ms", "INTEGER", 0),
            ("end_ms", "INTEGER", 0),
            ("text", "TEXT", 0),
        ], f"Unexpected subtitles schema: {schema}"
        actual_db = conn.execute(
            "SELECT id, start_ms, end_ms, text FROM subtitles ORDER BY id ASC"
        ).fetchall()
    finally:
        conn.close()
    assert actual_db == expected, "Database rows do not match the repaired raw input"


def run_pipeline():
    for path in (CLEAN, DB):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
    env = os.environ.copy()
    env["PATH"] = "/usr/local/go/bin:" + env.get("PATH", "")
    result = subprocess.run(
        ["go", "run", PIPELINE],
        cwd=HOME,
        env=env,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"pipeline.go failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_01_required_artifacts_and_original_assertions():
    assert os.path.exists(PIPELINE), f"Go pipeline missing: {PIPELINE}"
    mode = os.lstat(PIPELINE).st_mode
    assert stat.S_ISREG(mode), f"Expected a regular Go source file at {PIPELINE}"
    assert os.path.getsize(PIPELINE) > 0, f"Go pipeline is empty: {PIPELINE}"

    assert os.path.exists(DB), f"Database file missing: {DB}"
    assert os.path.isfile(DB), f"Expected a file at {DB}"
    assert os.path.getsize(DB) > 0, f"Database file is empty: {DB}"

    score = run_evaluator()
    assert score >= 0.95, f"LQS score {score} is below the required threshold of 0.95"

    assert os.path.exists(SCORE_FILE), f"Final score file missing: {SCORE_FILE}"
    assert os.path.isfile(SCORE_FILE), f"Expected a file at {SCORE_FILE}"
    with open(SCORE_FILE, encoding="utf-8") as f:
        content = f.read().strip()
    try:
        saved_score = float(content)
    except ValueError:
        pytest.fail(
            f"Contents of {SCORE_FILE} could not be parsed as a float. Content: {content}"
        )
    assert math.isfinite(saved_score)
    assert saved_score >= 0.95, (
        f"Score in {SCORE_FILE} ({saved_score}) is below the required threshold of 0.95"
    )


def test_02_original_outputs_are_complete_and_accurate():
    assert_outputs_match(RAW, required_count=10000)


def test_03_execute_pipeline_on_derived_input_and_restore_final_output():
    shutil.copyfile(RAW, RAW_BACKUP)
    try:
        with open(RAW, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "start_ms", "end_ms", "raw_text"])
            writer.writerow([1, 100, 150, "<i>Hello</i>, WORLD!"])
            writer.writerow([2, -1, -1, "  <c.color>Mixed</c.color>...   Spaces  "])
            writer.writerow([3, -1, -1, "<font color='red'>Testing</font>: one-two?"])
            writer.writerow([4, 110, 161, "Final; LINE!"])
        run_pipeline()
        assert_outputs_match(RAW, required_count=4)
    finally:
        shutil.copyfile(RAW_BACKUP, RAW)
        run_pipeline()

    assert_outputs_match(RAW, required_count=10000)


def test_04_lqs_and_saved_score_match_regenerated_database():
    score = run_evaluator()
    assert score >= 0.95, f"LQS score {score} is below the required threshold of 0.95"
    assert os.path.exists(SCORE_FILE), f"Final score file missing: {SCORE_FILE}"
    assert os.path.isfile(SCORE_FILE), f"Expected a file at {SCORE_FILE}"
    with open(SCORE_FILE, encoding="utf-8") as f:
        content = f.read().strip()
    try:
        saved_score = float(content)
    except ValueError:
        pytest.fail(
            f"Contents of {SCORE_FILE} could not be parsed as a float. Content: {content}"
        )
    assert math.isfinite(saved_score)
    assert saved_score >= 0.95
    assert abs(saved_score - score) <= 0.00005, (
        f"Saved score {saved_score} does not match evaluator output {score}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
