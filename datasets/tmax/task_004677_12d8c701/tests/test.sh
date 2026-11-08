#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

SOURCE = "/home/user/analyze_graph.c"
EXECUTABLE = "/home/user/analyze_graph"
DATABASE = "/home/user/dataset.db"
OUTPUT = "/home/user/frequent_citations.csv"
HEADER = ["Citing_Author_Name", "Cited_Author_Name", "Citation_Count"]


def test_c_source_exists():
    assert os.path.isfile(SOURCE), f"C source file not found at {SOURCE}"


def test_executable_exists_and_executable():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "analyze_graph must be a compiled executable"


def test_csv_output_correct():
    assert os.path.isfile(OUTPUT), f"CSV output file not found at {OUTPUT}"

    with open(OUTPUT, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_content = (
        "Citing_Author_Name,Cited_Author_Name,Citation_Count\n"
        "Alice,Charlie,3\n"
        "Eve,Alice,2"
    )

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, (
        f"CSV content does not match expected output.\nExpected:\n{expected_content}"
        f"\n\nActual:\n{content}"
    )


def make_case(tag):
    suffix = secrets.token_hex(6)
    ids = [f"{tag}_a{i}_{suffix}" for i in range(6)]
    prefixes = ["Aster", "Beryl", "Cedar", "Dune", "Ember", "Frost"]
    names = {aid: f"{prefix}_{suffix}" for aid, prefix in zip(ids, prefixes)}

    documents = {
        f"{tag}_s1": [ids[0], ids[1]],
        f"{tag}_s2": [ids[0]],
        f"{tag}_s3": [ids[3]],
        f"{tag}_s4": [ids[4]],
        f"{tag}_joint": [ids[0], ids[2]],
        f"{tag}_t1": [ids[2]],
        f"{tag}_t2": [ids[2]],
        f"{tag}_t3": [ids[5]],
        f"{tag}_t4": [ids[5]],
    }
    citations = [
        (f"{tag}_s1", f"{tag}_t1"),
        (f"{tag}_s2", f"{tag}_t1"),
        (f"{tag}_s2", f"{tag}_t2"),
        (f"{tag}_s3", f"{tag}_t1"),
        (f"{tag}_s3", f"{tag}_t2"),
        (f"{tag}_s4", f"{tag}_t3"),
        (f"{tag}_s4", f"{tag}_t4"),
        (f"{tag}_joint", f"{tag}_t1"),
    ]
    return names, documents, citations


def install_database(case):
    names, documents, citations = case
    for extra in (DATABASE + "-wal", DATABASE + "-shm"):
        if os.path.exists(extra):
            os.remove(extra)
    if os.path.exists(DATABASE):
        os.remove(DATABASE)

    con = sqlite3.connect(DATABASE)
    try:
        con.executescript("""
            CREATE TABLE authors (auth_id TEXT, name TEXT);
            CREATE TABLE documents (doc_id TEXT, metadata TEXT);
            CREATE TABLE citations (source_doc TEXT, target_doc TEXT);
        """)
        con.executemany("INSERT INTO authors VALUES (?, ?)", names.items())
        con.executemany(
            "INSERT INTO documents VALUES (?, ?)",
            [(doc, json.dumps({"year": 2024, "authors": authors}))
             for doc, authors in documents.items()],
        )
        con.executemany("INSERT INTO citations VALUES (?, ?)", citations)
        con.commit()
    finally:
        con.close()


def derive_expected(case):
    names, documents, citations = case
    counts = {}
    for source, target in citations:
        for citing_id in documents[source]:
            for cited_id in documents[target]:
                if citing_id != cited_id:
                    key = (names[citing_id], names[cited_id])
                    counts[key] = counts.get(key, 0) + 1

    rows = [(citing, cited, count)
            for (citing, cited), count in counts.items() if count >= 2]
    rows.sort(key=lambda row: (-row[2], row[0], row[1]))
    return [[citing, cited, str(count)] for citing, cited, count in rows]


def run_and_check(program, case):
    install_database(case)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [program], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{program} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{program} did not create {OUTPUT}"

    with open(OUTPUT, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == HEADER, f"Incorrect CSV header from {program}: {rows[:1]}"
    expected = derive_expected(case)
    assert rows[1:] == expected, (
        f"Incorrect dynamically computed results from {program}.\n"
        f"Expected: {expected}\nActual: {rows[1:]}"
    )


def test_executable_and_source_analyze_dynamic_databases():
    original_db = open(DATABASE, "rb").read()
    original_csv_exists = os.path.exists(OUTPUT)
    original_csv = open(OUTPUT, "rb").read() if original_csv_exists else None
    rebuilt = os.path.join(tempfile.gettempdir(), f"analyze_graph_rebuilt_{secrets.token_hex(6)}")

    try:
        run_and_check(EXECUTABLE, make_case("installed"))

        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt, "-lsqlite3"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert compile_result.returncode == 0, (
            "analyze_graph.c could not be compiled with SQLite support:\n"
            + compile_result.stderr
        )
        run_and_check(rebuilt, make_case("rebuilt"))
    finally:
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
        for extra in (DATABASE + "-wal", DATABASE + "-shm"):
            if os.path.exists(extra):
                os.remove(extra)
        with open(DATABASE, "wb") as f:
            f.write(original_db)
        if original_csv_exists:
            with open(OUTPUT, "wb") as f:
                f.write(original_csv)
        elif os.path.exists(OUTPUT):
            os.remove(OUTPUT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
