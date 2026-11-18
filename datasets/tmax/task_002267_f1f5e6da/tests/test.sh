#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import csv
import io
import sqlite3
import shutil
import tempfile
import uuid
import re
import shlex
from contextlib import contextmanager

SCRIPT_PATH = "/home/user/analyze.sh"
DB_PATH = "/home/user/research_data.db"
EXPECTED_HEADER = ["dependent_name", "category", "depth", "category_rank"]


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def run_script(target_dataset, env=None):
    result = subprocess.run(
        ["bash", SCRIPT_PATH, target_dataset],
        capture_output=True,
        text=True,
        env=env
    )
    assert result.returncode == 0, f"Script failed for {target_dataset} with error:\n{result.stderr}"
    return result.stdout.strip()


def parse_output(output):
    rows = list(csv.reader(io.StringIO(output)))
    assert len(rows) > 0, "Output is empty"
    assert rows[0] == EXPECTED_HEADER, f"Expected header {EXPECTED_HEADER}, got {rows[0]}"
    assert all(len(row) == 4 for row in rows[1:]), f"Malformed CSV rows: {rows[1:]}"
    return rows[1:]


def test_analyze_dataset_c():
    output = run_script("Dataset_C")
    rows = list(csv.reader(io.StringIO(output)))
    assert len(rows) > 0, "Output is empty"
    header = rows[0]
    expected_header = ["dependent_name", "category", "depth", "category_rank"]
    assert header == expected_header, f"Expected header {expected_header}, got {header}"
    data_rows = rows[1:]
    data_set = {tuple(row) for row in data_rows}
    expected_data = {
        ("Dataset_B", "Genomics", "1", "1"),
        ("Dataset_A", "Genomics", "2", "2"),
        ("Dataset_E", "Genomics", "3", "3"),
        ("Dataset_F", "Proteomics", "2", "1"),
        ("Dataset_D", "Transcriptomics", "1", "1"),
        ("Dataset_G", "Transcriptomics", "3", "2")
    }
    assert data_set == expected_data, f"Expected data {expected_data}, got {data_set}"


def test_analyze_dataset_b():
    output = run_script("Dataset_B")
    rows = list(csv.reader(io.StringIO(output)))
    assert len(rows) > 0, "Output is empty"
    header = rows[0]
    expected_header = ["dependent_name", "category", "depth", "category_rank"]
    assert header == expected_header, f"Expected header {expected_header}, got {header}"
    data_rows = rows[1:]
    data_set = {tuple(row) for row in data_rows}
    expected_data = {
        ("Dataset_A", "Genomics", "1", "1"),
        ("Dataset_E", "Genomics", "2", "2"),
        ("Dataset_F", "Proteomics", "1", "1"),
        ("Dataset_G", "Transcriptomics", "2", "1")
    }
    assert data_set == expected_data, f"Expected data {expected_data}, got {data_set}"


@contextmanager
def capture_sqlite_invocations():
    sqlite_path = os.path.realpath(shutil.which("sqlite3"))
    real_path = sqlite_path + ".verifier-real-" + uuid.uuid4().hex
    fd, log_path = tempfile.mkstemp(prefix="sqlite-verifier-", suffix=".log")
    os.close(fd)
    os.rename(sqlite_path, real_path)
    wrapper = f'''#!/bin/bash
input_file=$(mktemp)
cat > "$input_file"
{{
  printf '%s\\n' '--- invocation arguments ---'
  printf '%s\\n' "$@"
  printf '%s\\n' '--- invocation stdin ---'
  cat "$input_file"
  printf '%s\\n' '--- end invocation ---'
}} >> {shlex.quote(log_path)}
{shlex.quote(real_path)} "$@" < "$input_file"
status=$?
rm -f "$input_file"
exit $status
'''
    try:
        with open(sqlite_path, "w") as f:
            f.write(wrapper)
        os.chmod(sqlite_path, 0o755)
        yield log_path
    finally:
        if os.path.exists(sqlite_path):
            os.remove(sqlite_path)
        os.rename(real_path, sqlite_path)
        if os.path.exists(log_path):
            os.remove(log_path)


def derive_expected(db_path, target_name):
    con = sqlite3.connect(db_path)
    try:
        nodes = {row[0]: (row[1], row[2]) for row in con.execute("SELECT id, name, category FROM nodes")}
        target_ids = [node_id for node_id, (name, _) in nodes.items() if name == target_name]
        assert len(target_ids) == 1
        reverse = {}
        for source_id, target_id in con.execute("SELECT source_id, target_id FROM edges"):
            reverse.setdefault(target_id, []).append(source_id)

        distances = {}
        frontier = [(target_ids[0], 0)]
        index = 0
        while index < len(frontier):
            current, depth = frontier[index]
            index += 1
            for dependent in reverse.get(current, []):
                new_depth = depth + 1
                if dependent not in distances or new_depth < distances[dependent]:
                    distances[dependent] = new_depth
                    frontier.append((dependent, new_depth))

        grouped = {}
        for node_id, depth in distances.items():
            if node_id == target_ids[0]:
                continue
            name, category = nodes[node_id]
            grouped.setdefault(category, []).append((depth, name))

        expected = []
        for category, members in grouped.items():
            for rank, (depth, name) in enumerate(sorted(members), start=1):
                expected.append((name, category, str(depth), str(rank)))
        return expected
    finally:
        con.close()


def test_dynamic_database_and_executed_sql_pipeline():
    backup = tempfile.NamedTemporaryFile(prefix="research-db-backup-", delete=False)
    backup.close()
    shutil.copy2(DB_PATH, backup.name)
    token = uuid.uuid4().hex
    target = "Target_" + token
    cat_x = "Category_X_" + token
    cat_y = "Category_Y_" + token
    cat_z = "Category_Z_" + token
    names = {
        "target": target,
        "a": "A_direct_" + token,
        "b": "B_indirect_" + token,
        "c": "C_direct_" + token,
        "d": "D_multipath_" + token,
        "e": "E_deep_" + token,
        "f": "F_other_" + token,
        "unrelated": "Unrelated_" + token,
    }

    try:
        os.remove(DB_PATH)
        con = sqlite3.connect(DB_PATH)
        con.executescript("""
            CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, category TEXT);
            CREATE TABLE edges (source_id INTEGER, target_id INTEGER);
        """)
        node_rows = [
            (101, names["target"], cat_z),
            (203, names["a"], cat_x),
            (307, names["b"], cat_x),
            (409, names["c"], cat_x),
            (503, names["d"], cat_y),
            (607, names["e"], cat_y),
            (709, names["f"], cat_z),
            (811, names["unrelated"], cat_x),
        ]
        edge_rows = [
            (203, 101),
            (409, 101),
            (307, 203),
            (503, 307),
            (503, 409),
            (607, 503),
            (709, 307),
        ]
        con.executemany("INSERT INTO nodes(id, name, category) VALUES (?, ?, ?)", node_rows)
        con.executemany("INSERT INTO edges(source_id, target_id) VALUES (?, ?)", edge_rows)
        con.commit()
        con.close()

        expected = derive_expected(DB_PATH, target)
        with capture_sqlite_invocations() as sql_log:
            output = run_script(target)
            with open(sql_log, "r", errors="replace") as f:
                executed_sql = f.read()

        actual_rows = parse_output(output)
        actual = [tuple(row) for row in actual_rows]
        assert len(actual) == len(set(actual)), f"Duplicate output rows found: {actual}"
        assert set(actual) == set(expected), f"Expected dynamically derived data {set(expected)}, got {set(actual)}"

        normalized = re.sub(r"\s+", " ", executed_sql.lower())
        assert re.search(r"\bwith\s+recursive\b", normalized), "The executed sqlite3 input did not contain a Recursive CTE"
        assert re.search(r"\b(row_number|rank|dense_rank)\s*\(", normalized), "The executed sqlite3 input did not contain a ranking window function"
        assert re.search(r"\bover\s*\(", normalized), "The ranking function was not used as a window function"
        assert re.search(r"\bpartition\s+by\b", normalized), "The executed window function did not partition by category"
    finally:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        shutil.copy2(backup.name, DB_PATH)
        os.remove(backup.name)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
