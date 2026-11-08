#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import re
import stat
import subprocess
from pathlib import Path

SCRIPT_PATH = "/home/user/audit_trace.sh"
RESULT_PATH = "/home/user/audit_result.csv"
DB_PATH = "/home/user/audit.db"

EXPECTED_CSV_CONTENT = """id,user_id,doc_id,timestamp,user_seq
1,alice,doc_A,2023-10-01 10:00:00,1
2,bob,doc_A,2023-10-01 10:05:00,1
4,alice,doc_A,2023-10-01 10:15:00,2
5,dave,doc_A,2023-10-01 10:20:00,1
6,bob,doc_A,2023-10-01 10:25:00,2
7,alice,doc_A,2023-10-01 10:30:00,3"""


def normalized_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def run_script(argument, require_success=True):
    # A real REINDEX writes the database. Resetting its mtime lets us verify that
    # executing the script performs a database write rather than merely printing data.
    old_ns = 946684800_000_000_000
    os.utime(DB_PATH, ns=(old_ns, old_ns))
    result = subprocess.run(
        [SCRIPT_PATH, argument],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=10,
    )
    if require_success:
        assert result.returncode == 0, result.stderr
    assert os.stat(DB_PATH).st_mtime_ns != old_ns, "Running the script did not execute a database-writing REINDEX"
    return result


def parse_csv_output(text):
    rows = list(csv.reader(io.StringIO(text)))
    assert rows, "Script produced no CSV output"
    assert rows[0] == ["id", "user_id", "doc_id", "timestamp", "user_seq"], "CSV header is not exact"
    assert all(len(row) == 5 for row in rows[1:]), "CSV contains malformed rows"
    return rows[1:]


def expected_chain(rows, start_id):
    by_parent = {}
    by_id = {}
    for row in rows:
        record = {
            "id": row[0],
            "user_id": row[1],
            "doc_id": row[2],
            "timestamp": row[3],
            "parent": row[4],
        }
        by_id[record["id"]] = record
        by_parent.setdefault(record["parent"], []).append(record)

    chain = []
    pending = [by_id[start_id]] if start_id in by_id else []
    seen = set()
    while pending:
        record = pending.pop(0)
        if record["id"] in seen:
            continue
        seen.add(record["id"])
        chain.append(record)
        pending.extend(by_parent.get(record["id"], []))

    per_user = {}
    seq = {}
    for record in chain:
        per_user.setdefault(record["user_id"], []).append(record)
    for records in per_user.values():
        for number, record in enumerate(sorted(records, key=lambda r: (r["timestamp"], r["id"])), 1):
            seq[record["id"]] = number

    return {
        record["id"]: [
            str(record["id"]),
            record["user_id"],
            record["doc_id"],
            record["timestamp"],
            str(seq[record["id"]]),
        ]
        for record in chain
    }


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script at {SCRIPT_PATH} is not executable"


def test_script_contains_required_sql_constructs_and_parameterization():
    content = Path(SCRIPT_PATH).read_text()
    assert "REINDEX" in content.upper(), "The script does not contain the required REINDEX command."
    assert re.search(r"\bWITH\s+RECURSIVE\b", content, re.IGNORECASE), "A Recursive CTE is required"
    assert re.search(r"\bROW_NUMBER\s*\(\s*\)\s*OVER\s*\(", content, re.IGNORECASE), "A ROW_NUMBER window function is required"

    parameter = re.search(r"\.parameter\s+set\s+([:@$][A-Za-z_]\w*|\?[0-9]+)", content, re.IGNORECASE)
    assert parameter, "The sqlite3 query must bind the access ID with a .parameter value"
    assert len(re.findall(re.escape(parameter.group(1)), content)) >= 2, "The bound parameter is not used by the SQL query"


def test_result_csv_exists():
    assert os.path.exists(RESULT_PATH), f"Result file not found at {RESULT_PATH}"
    assert os.path.isfile(RESULT_PATH), f"{RESULT_PATH} is not a file"


def test_result_csv_content():
    content = Path(RESULT_PATH).read_text().strip()
    assert normalized_lines(content) == normalized_lines(EXPECTED_CSV_CONTENT), "The content of the CSV file does not match the expected output."


def test_script_reproduces_required_result_when_executed():
    result = run_script("1")
    assert normalized_lines(result.stdout) == normalized_lines(EXPECTED_CSV_CONTENT)


def test_script_handles_unseen_chain_and_safe_argument_binding():
    original_db = Path(DB_PATH).read_bytes()
    original_mode = stat.S_IMODE(os.stat(DB_PATH).st_mode)
    try:
        import sqlite3
        connection = sqlite3.connect(DB_PATH)
        connection.executemany(
            "INSERT INTO access_logs(id,user_id,doc_id,timestamp,parent_access_id) VALUES(?,?,?,?,?)",
            [
                (91001, "eve,qa", "doc_X", "2024-02-01 08:00:00", None),
                (91002, "unrelated", "doc_Z", "2024-02-01 08:01:00", None),
                (91003, "frank", "doc_X", "2024-02-01 08:05:00", 91001),
                (91004, "eve,qa", "doc_X", "2024-02-01 08:10:00", 91003),
                (91005, "grace", "doc_X", "2024-02-01 08:07:00", 91001),
                (91006, "eve,qa", "doc_X", "2024-02-01 08:20:00", 91005),
            ],
        )
        connection.commit()
        all_rows = connection.execute(
            "SELECT id,user_id,doc_id,timestamp,parent_access_id FROM access_logs"
        ).fetchall()
        connection.close()

        expected = expected_chain(all_rows, 91001)
        actual_rows = parse_csv_output(run_script("91001").stdout)
        actual = {int(row[0]): row for row in actual_rows}
        assert actual == expected, "Script did not recursively query and sequence the unseen chain correctly"

        # A value that would alter SQL if directly interpolated must be treated only as a bound value.
        run_script("91001; DROP TABLE access_logs;--", require_success=False)
        connection = sqlite3.connect(DB_PATH)
        count = connection.execute("SELECT count(*) FROM access_logs").fetchone()[0]
        connection.close()
        assert count == len(all_rows), "Unsafe argument interpolation modified the database"
    finally:
        Path(DB_PATH).write_bytes(original_db)
        os.chmod(DB_PATH, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
