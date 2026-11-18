#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import sqlite3
import subprocess
import time

import pytest

CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
EXECUTABLE = "/home/user/cleaner"
SOURCE = "/home/user/cleaner.go"
AUDIO_FILE = "/app/data/run_id.wav"
EXPECTED_RUN_ID = 8024


def run_cleaner(corpus_path, audio_path, db_path):
    if os.path.exists(db_path):
        os.remove(db_path)
    with open(corpus_path, "rb") as f:
        return subprocess.run(
            [EXECUTABLE, "--audio", audio_path, "--db", db_path],
            stdin=f,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found. Did you compile the Go program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cleaner must be a compiled executable"


def test_required_go_implementation_and_streaming_source():
    assert os.path.isfile(SOURCE), f"Go source {SOURCE} is missing"
    source = open(SOURCE, "r", encoding="utf-8").read()
    assert re.search(r'[\"`]database/sql[\"`]', source), "cleaner.go must import database/sql"
    assert re.search(r'[\"`]github\.com/mattn/go-sqlite3[\"`]', source), "cleaner.go must import github.com/mattn/go-sqlite3"
    assert re.search(r'\bsql\s*\.\s*(Open|DB|Tx|Stmt)\b', source), "cleaner.go must actually use database/sql"
    assert "os.Stdin" in source, "cleaner.go must consume stdin"
    assert not re.search(r'\b(?:io|ioutil)\s*\.\s*ReadAll\s*\(', source), "stdin must not be loaded completely into memory"
    assert re.search(r'NewScanner|NewReader|NewDecoder|\.Read\s*\(', source), "stdin must be processed incrementally"

    metadata = subprocess.run(
        ["go", "version", "-m", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert metadata.returncode == 0, metadata.stderr
    assert "github.com/mattn/go-sqlite3" in metadata.stdout, "compiled cleaner must include the sqlite3 Go driver"


def test_evil_corpus_rejected():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".jsonl")]
    assert evil_files, "No evil corpus files found."

    bypassed = []
    for i, filename in enumerate(evil_files):
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        db_path = f"/tmp/evil_test_{i}.db"
        proc = run_cleaner(filepath, AUDIO_FILE, db_path)

        if not os.path.exists(db_path):
            continue

        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        try:
            cursor.execute("SELECT COUNT(*) FROM clean_logs")
            if cursor.fetchone()[0] > 0:
                bypassed.append(filename)
        except sqlite3.OperationalError:
            pass
        finally:
            conn.close()

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed)}"


def test_clean_corpus_accepted():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".jsonl")]
    assert clean_files, "No clean corpus files found."

    modified = []
    for i, filename in enumerate(clean_files):
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        db_path = f"/tmp/clean_test_{i}.db"

        with open(filepath, "r") as f:
            lines = [line.strip() for line in f if line.strip()]

        proc = run_cleaner(filepath, AUDIO_FILE, db_path)
        if not os.path.exists(db_path):
            modified.append(filename)
            continue

        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        try:
            cursor.execute("SELECT * FROM clean_logs ORDER BY timestamp ASC, id ASC")
            rows = cursor.fetchall()
            if len(rows) != len(lines):
                modified.append(filename)
                continue

            confidences = []
            valid = True
            for j, row in enumerate(rows):
                if row["run_id"] != EXPECTED_RUN_ID:
                    valid = False
                    break
                record = json.loads(lines[j])
                confidences.append(record["confidence"])
                expected_avg = sum(confidences[-5:]) / len(confidences[-5:])
                if abs(row["rolling_avg_conf"] - expected_avg) > 1e-4:
                    valid = False
                    break
            if not valid:
                modified.append(filename)
        except sqlite3.OperationalError:
            modified.append(filename)
        finally:
            conn.close()

    assert not modified, f"{len(modified)} of {len(clean_files)} clean modified or missing rows. Offending files: {', '.join(modified)}"


def test_randomized_audio_filtering_fields_schema_and_rolling_window():
    rng = random.SystemRandom()
    digits = [rng.randrange(1, 10)] + [rng.randrange(10) for _ in range(3)]
    expected_run_id = int("".join(map(str, digits)))
    words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
    audio_path = f"/tmp/run_{secrets.token_hex(8)}.wav"
    spoken = " ".join(words[d] for d in digits)
    made_audio = subprocess.run(
        ["espeak", "-s", "125", "-w", audio_path, spoken],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert made_audio.returncode == 0 and os.path.getsize(audio_path) > 44

    token = secrets.token_hex(8)
    valid = []
    special_transcripts = [
        "ordinary speech",
        "   ",
        "DROP  TABLE is not the exact blocked substring",
        "a < script> tag with a space",
        "discussion of deletion without the blocked phrase",
    ]
    for i in range(18):
        confidence = [0.0, 1.0, 0.125, 0.333333, 0.875][i] if i < 5 else rng.randrange(1, 10000) / 10000.0
        valid.append({
            "id": f"v-{token}-{i}-{secrets.token_hex(3)}",
            "timestamp": 1800000000 + rng.randrange(1, 1000000),
            "duration_sec": rng.randrange(1, 20000) / 1000.0,
            "confidence": confidence,
            "transcript": special_transcripts[i] if i < len(special_transcripts) else f"valid randomized transcript {token} {i}",
        })

    def bad(i, duration, confidence, transcript):
        return {
            "id": f"bad-{token}-{i}-{secrets.token_hex(3)}",
            "timestamp": 1700000000 + i,
            "duration_sec": duration,
            "confidence": confidence,
            "transcript": transcript,
        }

    invalid = [
        bad(0, 0.0, 0.5, "zero duration"),
        bad(1, -rng.randrange(1, 100) / 10.0, 0.5, "negative duration"),
        bad(2, 1.0, -0.0001, "low confidence"),
        bad(3, 1.0, 1.0001, "high confidence"),
        bad(4, 1.0, 0.5, ""),
        bad(5, 1.0, 0.5, "prefix <script> suffix"),
        bad(6, 1.0, 0.5, "prefix <ScRiPt> suffix"),
        bad(7, 1.0, 0.5, "please DROP TABLE accounts"),
        bad(8, 1.0, 0.5, "please drop table accounts"),
        bad(9, 1.0, 0.5, "DELETE FROM accounts"),
        bad(10, 1.0, 0.5, "DeLeTe FrOm accounts"),
    ]

    records = valid + invalid
    rng.shuffle(records)

    expected = {}
    recent = []
    invalid_ids = {r["id"] for r in invalid}
    for record in records:
        if record["id"] in invalid_ids:
            continue
        recent.append(record["confidence"])
        expected[record["id"]] = (record, sum(recent[-5:]) / len(recent[-5:]))

    db_path = f"/tmp/randomized_{secrets.token_hex(8)}.db"
    proc = subprocess.Popen(
        [EXECUTABLE, "--audio", audio_path, "--db", db_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    for i, record in enumerate(records):
        proc.stdin.write((json.dumps(record, separators=(",", ":")) + "\n").encode())
        proc.stdin.flush()
        if i % 7 == 0:
            time.sleep(0.01)
    proc.stdin.close()
    proc.stdin = None
    stdout, stderr = proc.communicate(timeout=120)
    assert proc.returncode == 0, f"cleaner exited {proc.returncode}: {stderr.decode(errors='replace')}"
    assert os.path.isfile(db_path), "cleaner did not create the requested database"

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        schema = conn.execute("PRAGMA table_info(clean_logs)").fetchall()
        assert [(r["name"], r["type"].upper()) for r in schema] == [
            ("id", "TEXT"),
            ("timestamp", "INTEGER"),
            ("duration_sec", "REAL"),
            ("transcript", "TEXT"),
            ("confidence", "REAL"),
            ("rolling_avg_conf", "REAL"),
            ("run_id", "INTEGER"),
        ]
        assert schema[0]["pk"] == 1, "id must be the primary key"
        assert all(r["pk"] == 0 for r in schema[1:])

        rows = conn.execute("SELECT * FROM clean_logs").fetchall()
        assert len(rows) == len(expected), "wrong number of valid records inserted"
        assert {row["id"] for row in rows} == set(expected), "inserted IDs do not exactly match valid input"

        for row in rows:
            source, expected_avg = expected[row["id"]]
            assert row["timestamp"] == source["timestamp"]
            assert abs(row["duration_sec"] - source["duration_sec"]) < 1e-9
            assert row["transcript"] == source["transcript"]
            assert abs(row["confidence"] - source["confidence"]) < 1e-9
            assert abs(row["rolling_avg_conf"] - expected_avg) < 1e-9
            assert row["run_id"] == expected_run_id
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
