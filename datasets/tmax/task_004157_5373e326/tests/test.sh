#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile
from collections import Counter


def read_csv_rows(path):
    rows = []
    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        first = next(reader, None)
        if first:
            assert len(first) >= 3, "CSV contains a malformed row"
            if first[0] != "service_id":
                rows.append((str(first[0]), str(first[1]), str(first[2])))
        for row in reader:
            assert len(row) >= 3, "CSV contains a malformed row"
            rows.append((str(row[0]), str(row[1]), str(row[2])))
    return rows


def test_video_glitches():
    glitches_file = "/home/user/video_glitches.txt"
    assert os.path.isfile(glitches_file), f"{glitches_file} is missing."

    with open(glitches_file, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n") if line.strip()]

    expected = ["45", "112", "280"]
    assert lines == expected, f"Expected video glitches to be {expected}, but got {lines}."


def test_database_repair_and_rolling_impact_csv():
    csv_file = "/home/user/rolling_impact.csv"
    db_file = "/home/user/system.db"
    source_file = "/home/user/db_analyze.go"

    assert os.path.isfile(csv_file), f"{csv_file} is missing."
    assert os.path.isfile(db_file), f"{db_file} is missing."
    assert os.path.isfile(source_file), f"{source_file} is missing."

    expected_events = [
        (1, "svc1", "2023-01-01 10:00:00", 10),
        (2, "svc1", "2023-01-01 10:05:00", 20),
        (3, "svc1", "2023-01-01 10:10:00", 30),
        (4, "svc1", "2023-01-01 10:15:00", 40),
        (5, "svc2", "2023-01-01 10:02:00", 5),
        (6, "svc2", "2023-01-01 10:07:00", 15),
        (7, "svc2", "2023-01-01 10:12:00", 25),
    ]
    expected_rows = Counter([
        ("svc1", "2023-01-01 10:00:00", "10"),
        ("svc1", "2023-01-01 10:05:00", "30"),
        ("svc1", "2023-01-01 10:10:00", "60"),
        ("svc1", "2023-01-01 10:15:00", "90"),
        ("svc2", "2023-01-01 10:02:00", "5"),
        ("svc2", "2023-01-01 10:07:00", "20"),
        ("svc2", "2023-01-01 10:12:00", "45"),
    ])

    conn = sqlite3.connect(db_file)
    try:
        assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "system.db failed integrity_check"
        actual_events = conn.execute(
            "SELECT id, service_id, event_time, impact_score FROM events ORDER BY id"
        ).fetchall()
        assert actual_events == expected_events, "The original events data was altered"

        indexes = {row[1]: row for row in conn.execute("PRAGMA index_list('events')").fetchall()}
        assert "idx_events" in indexes, "idx_events was not repaired"
        index_columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_events')").fetchall()]
        assert index_columns == ["event_time"], f"idx_events has incorrect columns: {index_columns}"
        index_sql_row = conn.execute(
            "SELECT sql FROM sqlite_master WHERE type='index' AND name='idx_events'"
        ).fetchone()
        assert index_sql_row and index_sql_row[0], "idx_events has no valid CREATE INDEX definition"
        assert "wrong_column" not in index_sql_row[0].lower(), "The corrupted index definition remains"
    finally:
        conn.close()

    assert Counter(read_csv_rows(csv_file)) == expected_rows, (
        "rolling_impact.csv does not contain the expected rolling window results"
    )

    with open(source_file, "r", encoding="utf-8") as f:
        source = f.read()
    assert re.search(r"\bpackage\s+main\b", source), "db_analyze.go is not a Go main program"
    assert re.search(r"\bOVER\s*\(", source, re.IGNORECASE), "db_analyze.go does not contain a window query"
    assert re.search(r"PARTITION\s+BY\s+service_id", source, re.IGNORECASE), "Window query does not partition by service_id"
    assert re.search(
        r"ROWS\s+BETWEEN\s+2\s+PRECEDING\s+AND\s+CURRENT\s+ROW", source, re.IGNORECASE
    ), "Window query does not use the last three events"


def test_db_analyze_executes_on_unseen_database():
    db_file = "/home/user/system.db"
    csv_file = "/home/user/rolling_impact.csv"
    source_file = "/home/user/db_analyze.go"

    with tempfile.TemporaryDirectory(prefix="db_analyze_verify_") as td:
        db_backup = os.path.join(td, "system.db.backup")
        csv_backup = os.path.join(td, "rolling_impact.csv.backup")
        shutil.copy2(db_file, db_backup)
        had_csv = os.path.exists(csv_file)
        if had_csv:
            shutil.copy2(csv_file, csv_backup)

        token = secrets.token_hex(6)
        services = [f"alpha_{token}", f"beta_{token}", f"gamma_{token}"]
        generated = []
        row_id = 1
        for service_num, service in enumerate(services):
            for event_num in range(5):
                timestamp = f"2041-0{service_num + 1}-{event_num + 1:02d} 12:{event_num * 7:02d}:00"
                score = secrets.randbelow(80) + 1
                generated.append((row_id, service, timestamp, score))
                row_id += 1

        try:
            for suffix in ("", "-wal", "-shm", "-journal"):
                try:
                    os.remove(db_file + suffix)
                except FileNotFoundError:
                    pass

            conn = sqlite3.connect(db_file)
            try:
                conn.execute(
                    "CREATE TABLE events (id INTEGER PRIMARY KEY, service_id TEXT, event_time TIMESTAMP, impact_score INTEGER)"
                )
                conn.executemany(
                    "INSERT INTO events(id, service_id, event_time, impact_score) VALUES (?, ?, ?, ?)", generated
                )
                conn.execute("CREATE INDEX idx_events ON events(event_time)")
                conn.commit()
                expected = Counter(
                    (str(a), str(b), str(c))
                    for a, b, c in conn.execute(
                        """
                        SELECT service_id, event_time,
                               SUM(impact_score) OVER (
                                   PARTITION BY service_id
                                   ORDER BY event_time
                                   ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
                               )
                        FROM events
                        """
                    ).fetchall()
                )
            finally:
                conn.close()

            try:
                os.remove(csv_file)
            except FileNotFoundError:
                pass

            result = subprocess.run(
                ["/usr/local/go/bin/go", "run", source_file],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=120,
            )
            assert result.returncode == 0, f"db_analyze.go failed on an unseen database:\n{result.stderr}"
            assert os.path.isfile(csv_file), "db_analyze.go did not create rolling_impact.csv"
            assert Counter(read_csv_rows(csv_file)) == expected, (
                "db_analyze.go did not calculate correct rolling sums for an unseen database"
            )
        finally:
            for suffix in ("", "-wal", "-shm", "-journal"):
                try:
                    os.remove(db_file + suffix)
                except FileNotFoundError:
                    pass
            shutil.copy2(db_backup, db_file)
            if had_csv:
                shutil.copy2(csv_backup, csv_file)
            else:
                try:
                    os.remove(csv_file)
                except FileNotFoundError:
                    pass


def test_sqlsanitize_adversarial_corpus():
    tool_path = "/home/user/sanitizer/sqlsanitize"
    evil_corpus = "/app/corpus/evil.txt"
    clean_corpus = "/app/corpus/clean.txt"

    assert os.path.isfile(tool_path), f"Sanitizer tool {tool_path} is missing."
    assert os.access(tool_path, os.X_OK), f"Sanitizer tool {tool_path} is not executable."

    result_evil = subprocess.run([tool_path, evil_corpus], capture_output=True, text=True, timeout=20)
    assert result_evil.returncode == 0, f"sqlsanitize failed on evil corpus with exit code {result_evil.returncode}."
    assert result_evil.stdout.strip() == "", (
        f"sqlsanitize failed to reject all evil queries. Output was not empty:\n{result_evil.stdout.strip()}"
    )

    result_clean = subprocess.run([tool_path, clean_corpus], capture_output=True, text=True, timeout=20)
    assert result_clean.returncode == 0, f"sqlsanitize failed on clean corpus with exit code {result_clean.returncode}."
    with open(clean_corpus, "r") as f:
        expected_clean_output = f.read().strip()
    assert result_clean.stdout.strip() == expected_clean_output, "sqlsanitize modified or rejected clean queries."


def test_sqlsanitize_rebuild_and_unseen_corpora():
    module_dir = "/home/user/sanitizer"
    assert os.path.isfile(os.path.join(module_dir, "go.mod")), "sanitizer is not a Go module"
    assert any(name.endswith(".go") for name in os.listdir(module_dir)), "sanitizer has no Go source files"

    with tempfile.TemporaryDirectory(prefix="sanitize_verify_") as td:
        rebuilt = os.path.join(td, "sqlsanitize")
        build = subprocess.run(
            ["/usr/local/go/bin/go", "build", "-o", rebuilt, "."],
            cwd=module_dir,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert build.returncode == 0, f"The sanitizer Go module does not build:\n{build.stderr}"

        token = secrets.token_hex(8)
        clean_lines = [
            f"SELECT id, event_time FROM events_{token} WHERE impact_score > {secrets.randbelow(50) + 1};",
            f"WITH cte_{token} AS (SELECT service_id FROM events_{token}) SELECT service_id FROM cte_{token};",
            f"SELECT service_id, sum(impact_score) FROM events_{token} GROUP BY service_id;",
        ]
        evil_lines = [
            f"SeLeCt id FROM users_{token} UnIoN    SeLeCt password FROM admin_{token};",
            f"DROP TABLE events_{token};",
            f"dElEtE FROM events_{token} WHERE id = {secrets.randbelow(1000)};",
            f"InSeRt INTO events_{token} (service_id) VALUES ('{token}');",
            f"uPdAtE events_{token} SET impact_score = {secrets.randbelow(100)};",
        ]

        clean_path = os.path.join(td, secrets.token_hex(6) + ".sql")
        evil_path = os.path.join(td, secrets.token_hex(6) + ".sql")
        mixed_path = os.path.join(td, secrets.token_hex(6) + ".sql")
        with open(clean_path, "w") as f:
            f.write("\n".join(clean_lines) + "\n")
        with open(evil_path, "w") as f:
            f.write("\n".join(evil_lines) + "\n")
        mixed_lines = [clean_lines[0], evil_lines[0], evil_lines[2], clean_lines[1], evil_lines[4], clean_lines[2]]
        with open(mixed_path, "w") as f:
            f.write("\n".join(mixed_lines) + "\n")

        evil_result = subprocess.run([rebuilt, evil_path], capture_output=True, text=True, timeout=20)
        assert evil_result.returncode == 0, f"Rebuilt sqlsanitize failed: {evil_result.stderr}"
        assert evil_result.stdout.strip() == "", "sqlsanitize accepted an unseen evil query"

        clean_result = subprocess.run([rebuilt, clean_path], capture_output=True, text=True, timeout=20)
        assert clean_result.returncode == 0, f"Rebuilt sqlsanitize failed: {clean_result.stderr}"
        assert clean_result.stdout.strip() == "\n".join(clean_lines), "sqlsanitize changed unseen clean queries"

        mixed_result = subprocess.run([rebuilt, mixed_path], capture_output=True, text=True, timeout=20)
        assert mixed_result.returncode == 0, f"Rebuilt sqlsanitize failed: {mixed_result.stderr}"
        assert mixed_result.stdout.strip() == "\n".join(clean_lines), (
            "sqlsanitize did not correctly filter an unseen mixed corpus"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
