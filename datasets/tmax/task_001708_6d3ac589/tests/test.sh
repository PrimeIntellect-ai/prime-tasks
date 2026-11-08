#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR="$(mktemp -d)"
cp /home/user/data/nodes.csv "$BACKUP_DIR/nodes.csv"
cp /home/user/data/edges.csv "$BACKUP_DIR/edges.csv"
SQLITE_REAL="/usr/bin/sqlite3.verifier-real"
TRACE_FILE="/tmp/sqlite-verifier-trace.jsonl"
rm -f "$TRACE_FILE"

cleanup() {
    cp "$BACKUP_DIR/nodes.csv" /home/user/data/nodes.csv 2>/dev/null || true
    cp "$BACKUP_DIR/edges.csv" /home/user/data/edges.csv 2>/dev/null || true
    rm -rf "$BACKUP_DIR"
    if [ -e "$SQLITE_REAL" ]; then
        rm -f /usr/bin/sqlite3
        mv "$SQLITE_REAL" /usr/bin/sqlite3
    fi
}
trap cleanup EXIT

mv /usr/bin/sqlite3 "$SQLITE_REAL"
cat << 'WRAPPER_EOF' > /usr/bin/sqlite3
#!/usr/bin/python3
import json
import os
import subprocess
import sys

real = "/usr/bin/sqlite3.verifier-real"
trace = "/tmp/sqlite-verifier-trace.jsonl"
data = sys.stdin.buffer.read()
proc = subprocess.run([real] + sys.argv[1:], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
record = {
    "argv": sys.argv[1:],
    "stdin": data.decode("utf-8", "replace"),
    "stdout": proc.stdout.decode("utf-8", "replace"),
    "stderr": proc.stderr.decode("utf-8", "replace"),
}
with open(trace, "a", encoding="utf-8") as f:
    f.write(json.dumps(record) + "\n")
sys.stdout.buffer.write(proc.stdout)
sys.stderr.buffer.write(proc.stderr)
sys.exit(proc.returncode)
WRAPPER_EOF
chmod +x /usr/bin/sqlite3

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import stat
import subprocess
import uuid
import pytest

SCRIPT_PATH = "/home/user/analyze_graph.sh"
QUERY_PLAN_PATH = "/home/user/query_plan.txt"
TRACE_PATH = "/tmp/sqlite-verifier-trace.jsonl"
NODES_PATH = "/home/user/data/nodes.csv"
EDGES_PATH = "/home/user/data/edges.csv"


def run_script(*args):
    return subprocess.run([SCRIPT_PATH, *args], capture_output=True, text=True, timeout=15)


def output_lines(stdout):
    return [line.strip() for line in stdout.strip().split("\n") if line.strip()]


def sqlite_files_under_home():
    found = []
    for root, dirs, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            try:
                if os.path.isfile(path):
                    with open(path, "rb") as f:
                        if f.read(16) == b"SQLite format 3\x00":
                            found.append(path)
            except OSError:
                pass
    return found


def read_trace():
    assert os.path.isfile(TRACE_PATH), "The script never invoked sqlite3."
    with open(TRACE_PATH, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_output_engineering():
    try:
        result = subprocess.run([SCRIPT_PATH, "Engineering"], capture_output=True, text=True, check=True, timeout=15)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed with error: {e.stderr}")

    actual = output_lines(result.stdout)
    expected_lines = ["Alice,Charlie,Sales", "Alice,Grace,HR"]
    assert sorted(actual) == sorted(expected_lines), \
        f"Expected output for 'Engineering' to be {expected_lines}, but got {actual}"


def test_script_output_sales():
    try:
        result = subprocess.run([SCRIPT_PATH, "Sales"], capture_output=True, text=True, check=True, timeout=15)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed with error: {e.stderr}")

    actual = output_lines(result.stdout)
    expected_lines = ["Charlie,Diana,Marketing", "Frank,Grace,HR"]
    assert sorted(actual) == sorted(expected_lines), \
        f"Expected output for 'Sales' to be {expected_lines}, but got {actual}"


def test_query_plan_contains_index():
    assert os.path.isfile(QUERY_PLAN_PATH), f"Query plan file {QUERY_PLAN_PATH} does not exist."
    with open(QUERY_PLAN_PATH, "r") as f:
        content = f.read().upper()
    assert "INDEX" in content, f"The query plan in {QUERY_PLAN_PATH} does not demonstrate the use of an INDEX."


def test_exactly_one_argument_required():
    assert run_script().returncode != 0, "The script must reject zero arguments."
    assert run_script("Engineering", "extra").returncode != 0, "The script must reject more than one argument."


def test_dynamic_csv_data_is_imported_and_queried_with_sqlite():
    token = uuid.uuid4().hex[:10]
    target = "Dept_" + token
    other1 = "OutsideA_" + token
    other2 = "OutsideB_" + token
    names = ["MgrA_" + token, "Same_" + token, "EmpA_" + token,
             "MgrB_" + token, "EmpB_" + token, "OtherMgr_" + token]

    with open(NODES_PATH, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["node_id", "name", "department"])
        w.writerows([
            [101, names[0], target],
            [102, names[1], target],
            [103, names[2], other1],
            [104, names[3], target],
            [105, names[4], other2],
            [106, names[5], other1],
        ])
    with open(EDGES_PATH, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["manager_id", "employee_id"])
        w.writerows([
            [101, 102],
            [101, 103],
            [104, 105],
            [106, 101],
        ])

    if os.path.exists(QUERY_PLAN_PATH):
        os.remove(QUERY_PLAN_PATH)
    result = run_script(target)
    assert result.returncode == 0, f"Script failed on dynamic input: {result.stderr}"
    expected = [f"{names[0]},{names[2]},{other1}", f"{names[3]},{names[4]},{other2}"]
    assert sorted(output_lines(result.stdout)) == sorted(expected)

    assert sqlite_files_under_home() == [], "The script left a permanent SQLite database under /home/user."


def test_sqlite_operations_parameterization_and_real_query_plan():
    records = read_trace()
    assert records, "The script never invoked sqlite3."
    sql = "\n".join(" ".join(r.get("argv", [])) + "\n" + r.get("stdin", "") for r in records)

    assert re.search(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[\"`\[]?nodes\b", sql, re.I), \
        "SQLite SQL did not create the nodes table."
    assert re.search(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[\"`\[]?edges\b", sql, re.I), \
        "SQLite SQL did not create the edges table."
    assert re.search(r"\.import\b", sql, re.I) and NODES_PATH in sql and EDGES_PATH in sql, \
        "Both CSV files must be imported through sqlite3."

    index_matches = re.findall(
        r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?[\"`\[]?([A-Za-z_][\w.-]*)[\"`\]]?\s+ON\s+[\"`\[]?(nodes|edges)\b",
        sql, re.I)
    assert index_matches, "No index was created on the imported nodes or edges table."
    assert re.search(r"EXPLAIN\s+QUERY\s+PLAN", sql, re.I), "sqlite3 was not asked to execute EXPLAIN QUERY PLAN."
    assert re.search(r"\.parameter\s+(?:init|set)", sql, re.I), "The query did not use sqlite3 parameter binding."
    assert re.search(r"(?:WHERE|AND|OR)[\s\S]{0,300}(?:[:@$][A-Za-z_]\w*|\?[0-9]*)", sql, re.I), \
        "The query filter does not contain a bound parameter placeholder."

    assert os.path.isfile(QUERY_PLAN_PATH), "The dynamic run did not create query_plan.txt."
    with open(QUERY_PLAN_PATH, encoding="utf-8") as f:
        plan = f.read()
    assert re.search(r"USING\s+(?:COVERING\s+)?INDEX\b", plan, re.I), \
        "The actual query plan does not show an index being used."
    created_names = [name for name, _ in index_matches]
    assert any(re.search(r"\b" + re.escape(name) + r"\b", plan, re.I) for name in created_names), \
        "The query plan does not use an index created by the script."

    plan_from_stdout = any(plan.strip() and plan.strip() in r.get("stdout", "") for r in records)
    plan_via_sqlite_output = bool(re.search(
        r"\.(?:output|once)\s+[^\n]*query_plan\.txt[\s\S]*EXPLAIN\s+QUERY\s+PLAN|"
        r"EXPLAIN\s+QUERY\s+PLAN[\s\S]*\.(?:output|once)\s+[^\n]*query_plan\.txt",
        sql, re.I))
    assert plan_from_stdout or plan_via_sqlite_output, \
        "query_plan.txt was not shown to be exported from sqlite3's EXPLAIN QUERY PLAN output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
