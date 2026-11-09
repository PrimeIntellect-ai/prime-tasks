#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import secrets
import sqlite3
import stat
import subprocess

HOME = "/home/user"
DB_PATH = os.path.join(HOME, "graph.db")

ORIGINAL_ROWS = [
    ("A", "B", 20),
    ("A", "C", 40),
    ("B", "D", 60),
    ("E", "F", 10),
    ("G", "H", 80),
    ("A", "D", 10),
    ("B", "C", 30),
    ("C", "A", 100),
    ("E", "A", 60),
    ("G", "B", 30),
    ("H", "A", 10),
]


def read_edges(db_path):
    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='edges';")
        assert cursor.fetchone() is not None, "Table 'edges' does not exist in graph.db."

        cursor.execute("PRAGMA table_info(edges)")
        columns = [(row[1], row[2].upper()) for row in cursor.fetchall()]
        assert columns == [("source", "TEXT"), ("target", "TEXT"), ("weight", "INTEGER")], \
            f"Unexpected edges schema: {columns}"

        cursor.execute("SELECT source, target, weight FROM edges")
        return cursor.fetchall()
    finally:
        conn.close()


def test_graph_db_exists_and_populated():
    """Check that graph.db contains exactly all records from both supplied CSV files."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    actual = read_edges(DB_PATH)
    assert len(actual) == 11, \
        f"Expected 11 rows in 'edges' table, found {len(actual)}. The ETL pipeline might not have loaded both files successfully."
    assert collections.Counter(actual) == collections.Counter(ORIGINAL_ROWS), \
        f"The edges table does not exactly match the two supplied CSV files. Actual rows: {actual}"


def test_process_results_script_exists_and_executable():
    """Check if process_results.sh exists and is executable."""
    script_path = os.path.join(HOME, "process_results.sh")
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_report_txt_content():
    """Check if report.txt contains the correct aggregated and formatted results."""
    report_path = os.path.join(HOME, "report.txt")
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "Node: G, Weight: 110",
        "Node: C, Weight: 100",
        "Node: B, Weight: 90",
        "Total Top 3 Weight: 300"
    ]
    expected_content = "\n".join(expected_lines)
    assert content == expected_content, \
        f"Content of {report_path} does not match the expected output.\nExpected:\n{expected_content}\n\nActual:\n{content}"


def test_scripts_execute_pipeline_on_derived_inputs():
    """Execute both scripts on fresh inputs and derive all expected results independently."""
    etl_script = os.path.join(HOME, "etl_runner.sh")
    process_script = os.path.join(HOME, "process_results.sh")
    assert os.path.isfile(etl_script), f"Script {etl_script} does not exist."
    assert os.path.isfile(process_script), f"Script {process_script} does not exist."
    assert os.access(process_script, os.X_OK), f"Script {process_script} is not executable."

    suffix = secrets.token_hex(5)
    k = 60 + secrets.randbelow(31)
    names = [f"A_{suffix}", f"B_{suffix}", f"C_{suffix}",
             f"D_{suffix}", f"E_{suffix}", f"F_{suffix}"]
    totals = [k + 50, k + 30, k + 30, k + 10, 50, 49]

    rows = []
    for i, (source, total) in enumerate(zip(names, totals)):
        first = 1 + secrets.randbelow(total - 1)
        rows.append((source, f"target_{i}_a_{suffix}", first))
        rows.append((source, f"target_{i}_b_{suffix}", total - first))

    # Put portions of every source in each file so both inputs must be loaded.
    rows1 = rows[::2]
    rows2 = rows[1::2]

    mutable_paths = [
        os.path.join(HOME, "transactions1.csv"),
        os.path.join(HOME, "transactions2.csv"),
        os.path.join(HOME, "report.txt"),
        DB_PATH,
        DB_PATH + "-wal",
        DB_PATH + "-shm",
        DB_PATH + "-journal",
    ]
    backups = {}
    for path in mutable_paths:
        if os.path.exists(path):
            st = os.stat(path)
            with open(path, "rb") as f:
                backups[path] = (f.read(), stat.S_IMODE(st.st_mode))
        else:
            backups[path] = None

    def write_csv(path, csv_rows):
        with open(path, "w", newline="") as f:
            for source, target, weight in csv_rows:
                f.write(f"{source},{target},{weight}\n")

    try:
        for path in [DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm", DB_PATH + "-journal",
                     os.path.join(HOME, "report.txt")]:
            if os.path.exists(path):
                os.remove(path)
        write_csv(os.path.join(HOME, "transactions1.csv"), rows1)
        write_csv(os.path.join(HOME, "transactions2.csv"), rows2)

        etl_run = subprocess.run(
            ["/bin/bash", etl_script], cwd=HOME, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert etl_run.returncode == 0, \
            f"etl_runner.sh failed with exit code {etl_run.returncode}.\nstdout:\n{etl_run.stdout}\nstderr:\n{etl_run.stderr}"
        assert os.path.isfile(DB_PATH), "etl_runner.sh did not create graph.db."

        actual_rows = read_edges(DB_PATH)
        assert collections.Counter(actual_rows) == collections.Counter(rows), \
            f"Fresh ETL execution did not load exactly both CSV files.\nExpected: {rows}\nActual: {actual_rows}"

        process_run = subprocess.run(
            [process_script], cwd=HOME, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert process_run.returncode == 0, \
            f"process_results.sh failed with exit code {process_run.returncode}.\nstdout:\n{process_run.stdout}\nstderr:\n{process_run.stderr}"

        grouped = collections.defaultdict(int)
        for source, _target, weight in rows:
            grouped[source] += weight
        top = sorted(
            ((source, total) for source, total in grouped.items() if total > 50),
            key=lambda item: (-item[1], item[0])
        )[:3]
        expected_lines = [f"Node: {source}, Weight: {total}" for source, total in top]
        expected_lines.append(f"Total Top 3 Weight: {sum(total for _, total in top)}")
        expected_report = "\n".join(expected_lines)

        report_path = os.path.join(HOME, "report.txt")
        assert os.path.isfile(report_path), "process_results.sh did not create report.txt."
        with open(report_path, "r") as f:
            actual_report = f.read().strip()
        assert actual_report == expected_report, \
            f"process_results.sh produced an incorrect report.\nExpected:\n{expected_report}\n\nActual:\n{actual_report}"
    finally:
        for path in mutable_paths:
            if os.path.exists(path):
                os.remove(path)
        for path, backup in backups.items():
            if backup is not None:
                data, mode = backup
                with open(path, "wb") as f:
                    f.write(data)
                os.chmod(path, mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
