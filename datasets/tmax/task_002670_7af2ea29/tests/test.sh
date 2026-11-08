#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

DB=/home/user/research_data.sqlite
BACKUP=/tmp/research_data.sqlite.verifier_backup

if [ ! -f "$DB" ]; then
    exit 0
fi

if ! cp -p "$DB" "$BACKUP"; then
    exit 0
fi

cleanup() {
    rm -f "${DB}-wal" "${DB}-shm" "${DB}-journal"
    cp -p "$BACKUP" "$DB" 2>/dev/null || true
    rm -f "$BACKUP"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess
import uuid

CPP_PATH = "/home/user/extract.cpp"
EXE_PATH = "/home/user/extract"
TSV_PATH = "/home/user/author_citations.tsv"
DB_PATH = "/home/user/research_data.sqlite"


def run_extractor():
    if os.path.lexists(TSV_PATH):
        os.unlink(TSV_PATH)
    subprocess.run([EXE_PATH], cwd="/home/user", check=True, timeout=30)
    assert os.path.isfile(TSV_PATH), f"Output file {TSV_PATH} does not exist after execution."


def test_extract_cpp_exists():
    cpp_path = "/home/user/extract.cpp"
    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} does not exist."


def test_compile_and_execute_extractor():
    if os.path.lexists(EXE_PATH):
        os.unlink(EXE_PATH)
    subprocess.run(
        ["g++", "-std=c++17", CPP_PATH, "-lsqlite3", "-o", EXE_PATH],
        check=True,
        timeout=60,
    )
    assert os.path.isfile(EXE_PATH), "Compilation did not create /home/user/extract."

    symbols = subprocess.run(
        ["nm", "-D", EXE_PATH], capture_output=True, text=True, check=True, timeout=10
    ).stdout
    assert re.search(r"\bU sqlite3_[A-Za-z0-9_]+", symbols), (
        "The compiled program does not reference the SQLite3 C API."
    )
    run_extractor()


def test_author_citations_output():
    tsv_path = "/home/user/author_citations.tsv"
    assert os.path.isfile(tsv_path), f"Output file {tsv_path} does not exist."

    expected_lines = [
        "Dave Davis\tAlice Smith\t2",
        "Alice Smith\tBob Jones\t1",
        "Alice Smith\tCharlie Brown\t1",
        "Dave Davis\tCharlie Brown\t1"
    ]

    with open(tsv_path, 'r', encoding='utf-8') as f:
        actual_lines = [line.strip('\r\n') for line in f if line.strip('\r\n')]

    assert actual_lines == expected_lines, (
        f"Contents of {tsv_path} do not match expected output.\n"
        f"Expected:\n{expected_lines}\n"
        f"Actual:\n{actual_lines}"
    )


def test_extractor_queries_database_and_handles_new_data():
    token = uuid.uuid4().hex[:12]
    source_name = f"Probe Source {token}"
    target_name = f"Probe Target {token}"
    other_name = f"Probe Other {token}"

    conn = sqlite3.connect(DB_PATH)
    try:
        author_base = conn.execute("SELECT COALESCE(MAX(id), 0) + 1000 FROM tbl_A").fetchone()[0]
        paper_base = conn.execute("SELECT COALESCE(MAX(id), 0) + 1000 FROM tbl_B").fetchone()[0]
        source_id, target_id, other_id = author_base, author_base + 1, author_base + 2
        p1, p2, p3 = paper_base, paper_base + 1, paper_base + 2

        conn.executemany("INSERT INTO tbl_A(id, str_val) VALUES (?, ?)", [
            (source_id, source_name),
            (target_id, target_name),
            (other_id, other_name),
        ])
        conn.executemany("INSERT INTO tbl_B(id, str_val, num_val) VALUES (?, ?, ?)", [
            (p1, f"Probe Paper One {token}", 2022),
            (p2, f"Probe Paper Two {token}", 2023),
            (p3, f"Probe Paper Three {token}", 2024),
        ])
        conn.executemany("INSERT INTO tbl_C(x_id, y_id) VALUES (?, ?)", [
            (source_id, p1),
            (source_id, p2),
            (target_id, p2),
            (other_id, p3),
        ])
        conn.executemany("INSERT INTO tbl_D(u_id, v_id) VALUES (?, ?)", [
            (p1, p2),
            (p1, p2),
            (p1, p3),
            (p2, p3),
            (p3, p1),
        ])
        conn.commit()

        rows = conn.execute("""
            SELECT source_author.str_val, target_author.str_val, COUNT(*) AS weight
            FROM tbl_D AS citation
            JOIN tbl_C AS source_authorship
              ON source_authorship.y_id = citation.u_id
            JOIN tbl_A AS source_author
              ON source_author.id = source_authorship.x_id
            JOIN tbl_C AS target_authorship
              ON target_authorship.y_id = citation.v_id
            JOIN tbl_A AS target_author
              ON target_author.id = target_authorship.x_id
            WHERE source_author.id <> target_author.id
            GROUP BY source_author.id, source_author.str_val,
                     target_author.id, target_author.str_val
            ORDER BY weight DESC, source_author.str_val ASC, target_author.str_val ASC
        """).fetchall()
        expected_lines = [f"{source}\t{target}\t{weight}" for source, target, weight in rows]
    finally:
        conn.close()

    run_extractor()
    with open(TSV_PATH, "r", encoding="utf-8") as output:
        actual_lines = output.read().splitlines()

    assert actual_lines == expected_lines, (
        "The executable did not derive the graph from the modified database.\n"
        f"Expected:\n{expected_lines}\nActual:\n{actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
