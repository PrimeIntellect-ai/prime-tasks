#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import re
import sqlite3
import subprocess
import tempfile

EXECUTABLE = "/home/user/filter_edges"
SOURCE = "/home/user/filter_edges.c"
CLEANED = "/home/user/cleaned_graph.csv"
SQL_SCRIPT = "/home/user/analyze.sql"
DATABASE = "/home/user/graph.db"
REPORT = "/home/user/final_report.csv"
HEADER = "source_id,target_id,weight,timestamp"


def is_corrupt(source_id, target_id, weight):
    return weight < 100 and (source_id + target_id) % 7 == 0


def normalized_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def expected_filter_output(path):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == HEADER.split(",")
    kept = [HEADER]
    for row in rows[1:]:
        assert len(row) == 4
        source_id, target_id, weight, _ = map(int, row)
        if not is_corrupt(source_id, target_id, weight):
            kept.append(",".join(row))
    return kept


def run_filter(executable, path):
    result = subprocess.run(
        [executable, path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    assert result.stderr == "", "filter_edges must emit rows only to stdout"
    return normalized_lines(result.stdout)


def expected_main_rows():
    rows = []
    with open("/app/raw_graph.csv", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            values = tuple(int(row[name]) for name in
                           ("source_id", "target_id", "weight", "timestamp"))
            if not is_corrupt(values[0], values[1], values[2]):
                rows.append(values)
    return rows


def test_filter_edges_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Missing executable: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File is not executable: {EXECUTABLE}"


def test_adversarial_corpus_clean():
    clean_dir = "/app/corpora/clean/"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    assert clean_files, f"No clean corpus files found in {clean_dir}"
    for path in clean_files:
        assert run_filter(EXECUTABLE, path) == expected_filter_output(path)


def test_adversarial_corpus_evil():
    evil_dir = "/app/corpora/evil/"
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    assert evil_files, f"No evil corpus files found in {evil_dir}"
    for path in evil_files:
        assert run_filter(EXECUTABLE, path) == expected_filter_output(path)
        assert expected_filter_output(path) == [HEADER]


def test_c_source_compiles_and_both_binaries_handle_derived_corpus():
    assert os.path.isfile(SOURCE), f"Missing C source: {SOURCE}"
    assert os.path.getsize(SOURCE) > 0, "filter_edges.c is empty"

    rebuilt = "/tmp/filter_edges_rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", rebuilt],
        capture_output=True, text=True, timeout=20
    )
    assert compile_result.returncode == 0, compile_result.stderr

    fd, corpus = tempfile.mkstemp(prefix="filter-derived-", suffix=".csv")
    os.close(fd)
    lines = [HEADER]
    for source_id in range(31, 48):
        for target_id in range(53, 61):
            weight = ((source_id * 29 + target_id * 17) % 180) - 20
            timestamp = 1700000000 + source_id * 100 + target_id
            lines.append(f"{source_id},{target_id},{weight},{timestamp}")
    with open(corpus, "w", newline="") as f:
        f.write("\n".join(lines) + "\n")

    try:
        expected = expected_filter_output(corpus)
        assert run_filter(EXECUTABLE, corpus) == expected
        assert run_filter(rebuilt, corpus) == expected
    finally:
        os.unlink(corpus)
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)


def test_cleaned_graph_matches_filtering_of_raw_export():
    assert os.path.isfile(CLEANED), f"Missing cleaned graph: {CLEANED}"
    assert normalized_lines(open(CLEANED).read()) == expected_filter_output("/app/raw_graph.csv")


def test_graph_database_contains_exact_cleaned_edges():
    assert os.path.isfile(DATABASE), f"Missing database: {DATABASE}"
    connection = sqlite3.connect(DATABASE)
    try:
        schema = connection.execute("PRAGMA table_info(edges)").fetchall()
        assert [row[1] for row in schema] == [
            "source_id", "target_id", "weight", "timestamp"
        ]
        assert all("INT" in row[2].upper() for row in schema)
        actual = connection.execute(
            "SELECT source_id,target_id,weight,timestamp FROM edges "
            "ORDER BY source_id,target_id,weight,timestamp"
        ).fetchall()
    finally:
        connection.close()
    assert actual == sorted(expected_main_rows())


def test_analyze_sql_exists_and_uses_window_function():
    assert os.path.isfile(SQL_SCRIPT), f"Missing SQL script: {SQL_SCRIPT}"
    sql = open(SQL_SCRIPT).read()
    without_comments = re.sub(r"/\\*.*?\\*/", " ", sql, flags=re.S)
    without_comments = re.sub(r"--[^\\n]*", " ", without_comments)
    pattern = r"\\b(?:row_number|rank|dense_rank)\\s*\\([^)]*\\)\\s*over\\s*\\("
    assert re.search(pattern, without_comments, flags=re.I), \
        "analyze.sql must use a SQL window ranking function"


def test_final_report_content():
    assert os.path.isfile(REPORT), f"Missing final report: {REPORT}"
    # Correct filtering leaves nine ranked rows, so OFFSET 10 returns no data rows.
    assert normalized_lines(open(REPORT).read()) == [
        "source_id,target_id,weight,rank"
    ]


def test_analyze_sql_executes_on_derived_data_with_pagination():
    cleaned_backup = open(CLEANED, "rb").read()
    report_backup = open(REPORT, "rb").read()

    fixture_rows = []
    for source_id in range(20, 30):
        for target_id, weight in [(101, 500), (102, 300), (103, 300),
                                  (104, 100), (105, 50)]:
            fixture_rows.append((source_id, target_id, weight,
                                 1800000000 + source_id * 10 + target_id))

    ranked = []
    for source_id in range(20, 30):
        group = [row for row in fixture_rows if row[0] == source_id]
        group.sort(key=lambda row: (-row[2], row[1]))
        for rank, row in enumerate(group[:3], 1):
            ranked.append((row[0], row[1], row[2], rank))
    expected_report = ranked[10:25]

    temp_db = "/tmp/analyze-derived.db"
    if os.path.exists(temp_db):
        os.unlink(temp_db)

    try:
        with open(CLEANED, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(HEADER.split(","))
            writer.writerows(fixture_rows)
        os.unlink(REPORT)

        with open(SQL_SCRIPT, "rb") as script:
            result = subprocess.run(
                ["sqlite3", temp_db], stdin=script,
                capture_output=True, timeout=20
            )
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.isfile(REPORT), \
            "analyze.sql did not create /home/user/final_report.csv"

        with open(REPORT, newline="") as f:
            output = list(csv.reader(f))
        assert output and output[0] == ["source_id", "target_id", "weight", "rank"]
        actual_report = [tuple(map(int, row)) for row in output[1:]]
        assert actual_report == expected_report
        assert len(actual_report) == 15

        connection = sqlite3.connect(temp_db)
        try:
            imported = connection.execute(
                "SELECT source_id,target_id,weight,timestamp FROM edges "
                "ORDER BY source_id,target_id"
            ).fetchall()
        finally:
            connection.close()
        assert imported == sorted(fixture_rows)
    finally:
        with open(CLEANED, "wb") as f:
            f.write(cleaned_backup)
        with open(REPORT, "wb") as f:
            f.write(report_backup)
        if os.path.exists(temp_db):
            os.unlink(temp_db)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
