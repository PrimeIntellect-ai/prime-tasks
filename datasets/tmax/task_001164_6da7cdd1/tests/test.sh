#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import uuid

C_FILE_PATH = "/home/user/query_graph.c"
EXEC_PATH = "/home/user/query_graph"
OUTPUT_PATH = "/home/user/output.csv"
DB_PATH = "/home/user/knowledge_graph.db"

EXPECTED_CSV_CONTENT = """Author_Name,Dataset_Name
Alice Smith,GraphDB-1M
Bob Jones,GraphDB-1M
Charlie Brown,ImageNet-Mini
"""

QUERY = """
SELECT a.name, d.name
FROM nodes AS a
JOIN edges AS e1 ON e1.source = a.id AND e1.relation = 'authored'
JOIN nodes AS p ON p.id = e1.target AND p.type = 'Paper'
JOIN edges AS e2 ON e2.source = p.id AND e2.relation = 'uses'
JOIN nodes AS d ON d.id = e2.target AND d.type = 'Dataset'
JOIN edges AS e3 ON e3.source = d.id AND e3.relation = 'tagged'
JOIN nodes AS t ON t.id = e3.target AND t.type = 'Topic'
WHERE a.type = 'Author' AND t.name = 'Machine Learning'
ORDER BY a.name ASC, d.name ASC
"""


def read_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    with open(OUTPUT_PATH, "r", newline="") as f:
        return f.read()


def run_program(path):
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    subprocess.run([path], cwd="/home/user", check=True, timeout=15)
    return read_output()


def test_c_source_exists():
    assert os.path.isfile(C_FILE_PATH), f"C source file {C_FILE_PATH} is missing."


def test_executable_exists():
    assert os.path.isfile(EXEC_PATH), f"Compiled executable {EXEC_PATH} is missing."
    assert os.access(EXEC_PATH, os.X_OK), f"File {EXEC_PATH} is not executable."


def test_output_csv_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."


def test_output_csv_content():
    content = read_output()
    assert content.strip() == EXPECTED_CSV_CONTENT.strip(), "The contents of output.csv do not match the expected output."
    lines = content.strip().split('\n')
    assert lines[0] == "Author_Name,Dataset_Name", "The CSV header is incorrect."
    assert content == EXPECTED_CSV_CONTENT, "output.csv must have exact CSV formatting and one final Unix newline."


def test_program_is_compilable_uses_sqlite_and_queries_database():
    # Execute the artifact requested by the instruction rather than trusting the
    # pre-generated CSV.
    assert run_program(EXEC_PATH) == EXPECTED_CSV_CONTENT

    # Compile the submitted source and install that build at the required path,
    # proving that the source and final executable correspond.
    built_path = "/tmp/query_graph_from_submission"
    subprocess.run(
        ["gcc", C_FILE_PATH, "-o", built_path, "-lsqlite3"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )

    symbols = subprocess.run(
        ["nm", "-D", built_path],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    ).stdout
    sqlite_symbols = set(re.findall(r"sqlite3_[A-Za-z0-9_]+", symbols))
    assert {"sqlite3_open", "sqlite3_open_v2"} & sqlite_symbols, "Program does not use the SQLite C API to open the database."
    query_api_used = (
        "sqlite3_exec" in sqlite_symbols
        or "sqlite3_get_table" in sqlite_symbols
        or (({"sqlite3_prepare", "sqlite3_prepare_v2", "sqlite3_prepare_v3"} & sqlite_symbols) and "sqlite3_step" in sqlite_symbols)
    )
    assert query_api_used, "Program does not use a SQLite C query API."

    os.replace(built_path, EXEC_PATH)
    os.chmod(EXEC_PATH, 0o755)

    # Make an unpredictable database change and derive the expected answer from
    # the graph itself. This rejects programs that merely hardcode the known CSV.
    backup_path = f"/tmp/knowledge_graph_backup_{uuid.uuid4().hex}.db"
    src = sqlite3.connect(DB_PATH)
    backup = sqlite3.connect(backup_path)
    src.backup(backup)
    backup.close()
    src.close()

    token = uuid.uuid4().hex[:12]
    try:
        conn = sqlite3.connect(DB_PATH)
        next_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM nodes").fetchone()[0]
        author_id, paper_id, dataset_id = next_id, next_id + 1, next_id + 2
        topic_id = conn.execute(
            "SELECT id FROM nodes WHERE type='Topic' AND name='Machine Learning' ORDER BY id LIMIT 1"
        ).fetchone()[0]

        conn.execute("UPDATE nodes SET name=? WHERE id=1", (f"Zed Dynamic Author {token}",))
        conn.execute("UPDATE nodes SET name=? WHERE id=7", (f"Dynamic Dataset {token}",))
        conn.executemany(
            "INSERT INTO nodes(id, type, name) VALUES (?, ?, ?)",
            [
                (author_id, "Author", f"Dynamic Author {token}"),
                (paper_id, "Paper", f"Dynamic Paper {token}"),
                (dataset_id, "Dataset", f"Verifier Dataset {token}"),
            ],
        )
        conn.executemany(
            "INSERT INTO edges(source, target, relation) VALUES (?, ?, ?)",
            [
                (author_id, paper_id, "authored"),
                (paper_id, dataset_id, "uses"),
                (dataset_id, topic_id, "tagged"),
            ],
        )
        conn.commit()
        rows = conn.execute(QUERY).fetchall()
        conn.close()

        expected = "Author_Name,Dataset_Name\n" + "".join(f"{author},{dataset}\n" for author, dataset in rows)
        actual = run_program(EXEC_PATH)
        assert actual == expected, "The compiled program did not query the current database and emit the required ordered CSV."
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.unlink(path)
        shutil.copy2(backup_path, DB_PATH)
        os.chmod(DB_PATH, 0o777)
        os.unlink(backup_path)

    # Leave the required output generated from the original database.
    assert run_program(EXEC_PATH) == EXPECTED_CSV_CONTENT
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
