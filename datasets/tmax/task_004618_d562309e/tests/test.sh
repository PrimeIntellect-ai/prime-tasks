#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import shutil
import sqlite3
import subprocess
import tempfile
import time
from collections import defaultdict

SOURCE_DIR = "/app/sqlite-src-3410200"
BINARY = os.path.join(SOURCE_DIR, "sqlite3")
SCRIPT = "/home/user/analyze.sh"
INPUT_CSV = "/home/user/sales_data.csv"
DATABASE = "/home/user/company.db"
OUTPUT_CSV = "/home/user/top_performers.csv"
TRACE_DIR = None


def test_makefile_fixed():
    makefile_path = os.path.join(SOURCE_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-DSQLITE_OMIT_CTE=1" not in content, "Makefile still contains -DSQLITE_OMIT_CTE=1"
    assert "-DSQLITE_OMIT_WINDOWFUNC=1" not in content, "Makefile still contains -DSQLITE_OMIT_WINDOWFUNC=1"


def test_sqlite_compiled():
    # Force the submitted build configuration to regenerate the requested artifact.
    if os.path.lexists(BINARY):
        os.remove(BINARY)
    result = subprocess.run(
        ["make", "-B", "sqlite3"], cwd=SOURCE_DIR,
        capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"SQLite build failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(BINARY), f"Compiled sqlite3 binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), "sqlite3 binary is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sqlite3 is not a compiled ELF executable"

    sql = (
        "WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<3), "
        "r AS (SELECT x, rank() OVER (ORDER BY x DESC) AS k FROM n) "
        "SELECT group_concat(x || ':' || k, ',') FROM r;"
    )
    result = subprocess.run([BINARY, ":memory:", sql], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Built sqlite3 cannot execute recursive/window SQL: {result.stderr}"
    assert result.stdout.strip() == "3:1,2:2,1:3", f"Unexpected SQLite analytical result: {result.stdout!r}"

    result = subprocess.run(
        [BINARY, ":memory:", "PRAGMA compile_options;"],
        capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0
    options = result.stdout.upper()
    assert "OMIT_CTE" not in options, "Built SQLite omits CTE support"
    assert "OMIT_WINDOWFUNC" not in options, "Built SQLite omits window functions"


def test_analyze_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), "Script is not executable"


def test_execution_time_and_output():
    global TRACE_DIR
    for path in (OUTPUT_CSV, DATABASE):
        if os.path.lexists(path):
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.remove(path)

    TRACE_DIR = tempfile.mkdtemp(prefix="sqlite-trace-")
    real_binary = os.path.join(SOURCE_DIR, ".sqlite3.verifier-real")
    os.replace(BINARY, real_binary)
    wrapper = f'''#!/bin/bash
trace_dir={TRACE_DIR!r}
real={real_binary!r}
base=$(mktemp "$trace_dir/call.XXXXXX")
infile="$base.stdin"
outfile="$base.stdout"
argsfile="$base.args"
pwd > "$base.cwd"
printf '%s\\n' "$@" > "$argsfile"
cat > "$infile"
cat "$argsfile" "$infile" > "$base.evidence"
# Preserve SQL loaded through the CLI's .read command as execution evidence.
grep -hEo '\\.read[[:space:]]+[^[:space:]]+' "$argsfile" "$infile" 2>/dev/null | while read -r spec; do
    p=${{spec#*.read}}
    p=$(printf '%s' "$p" | sed -e 's/^[[:space:]]*//' -e 's/^["'"']//' -e 's/["'"']$//')
    if [ -f "$p" ]; then cat "$p" >> "$base.evidence"; fi
done
"$real" "$@" < "$infile" > "$outfile"
rc=$?
cat "$outfile"
exit $rc
'''
    try:
        with open(BINARY, "w") as f:
            f.write(wrapper)
        os.chmod(BINARY, 0o755)

        start = time.time()
        result = subprocess.run([SCRIPT], capture_output=True, timeout=20)
        duration = time.time() - start
    finally:
        if os.path.lexists(BINARY):
            os.remove(BINARY)
        if os.path.exists(real_binary):
            os.replace(real_binary, BINARY)

    assert result.returncode == 0, f"analyze.sh failed with error:\n{result.stderr.decode(errors='replace')}"
    assert duration <= 15.0, f"Execution time {duration:.2f}s exceeded the 15.0s threshold"
    assert os.path.isfile(OUTPUT_CSV), f"Output CSV not generated at {OUTPUT_CSV}"
    assert os.path.isfile(DATABASE), f"SQLite database not generated at {DATABASE}"

    evidence_files = [os.path.join(TRACE_DIR, n) for n in os.listdir(TRACE_DIR) if n.endswith(".evidence")]
    assert evidence_files, "analyze.sh did not invoke the compiled sqlite3 binary"

    output_bytes = open(OUTPUT_CSV, "rb").read()
    analytical_call_found = False
    for evidence_path in evidence_files:
        evidence = open(evidence_path, "rb").read().decode("utf-8", errors="replace")
        has_recursive = re.search(r"\bWITH\s+RECURSIVE\b", evidence, re.I | re.S)
        has_rank = re.search(r"\bRANK\s*\(\s*\)\s*OVER\b", evidence, re.I | re.S)
        if not (has_recursive and has_rank):
            continue
        base = evidence_path[:-len(".evidence")]
        stdout_bytes = open(base + ".stdout", "rb").read() if os.path.exists(base + ".stdout") else b""
        names_output = re.search(r"(?:^|[/\\])top_performers\.csv\b", evidence, re.I) is not None
        stdout_is_output = bool(stdout_bytes) and stdout_bytes == output_bytes
        if names_output or stdout_is_output:
            analytical_call_found = True
            break
    assert analytical_call_found, (
        "No sqlite3 invocation both executed a recursive RANK window query and produced/directed "
        "the top_performers.csv output"
    )


def test_database_created_and_loaded():
    assert os.path.isfile(DATABASE), f"Database not found at {DATABASE}"
    with open(DATABASE, "rb") as f:
        assert f.read(16) == b"SQLite format 3\x00", "company.db is not a SQLite database"

    expected_count = 0
    expected_sales_sum = 0.0
    samples = {}
    with open(INPUT_CSV, newline="") as f:
        for row in csv.DictReader(f):
            expected_count += 1
            expected_sales_sum += float(row["individual_sales"])
            emp = int(row["emp_id"])
            if emp in (1, 50000, 100000):
                samples[emp] = row

    con = sqlite3.connect(f"file:{DATABASE}?mode=ro", uri=True)
    try:
        candidates = []
        for (name,) in con.execute("SELECT name FROM sqlite_master WHERE type='table'"):
            quoted = name.replace('"', '""')
            cols = {r[1] for r in con.execute(f'PRAGMA table_info("{quoted}")')}
            if {"emp_id", "manager_id", "dept_id", "individual_sales"}.issubset(cols):
                candidates.append(name)
        assert candidates, "company.db has no table containing the imported sales columns"

        matched = False
        for name in candidates:
            q = '"' + name.replace('"', '""') + '"'
            count, sales_sum = con.execute(
                f"SELECT count(*), sum(CAST(individual_sales AS REAL)) FROM {q}"
            ).fetchone()
            if count != expected_count or abs(float(sales_sum) - expected_sales_sum) > 1e-5:
                continue
            ok = True
            for emp, expected in samples.items():
                row = con.execute(
                    f"SELECT manager_id, dept_id, individual_sales FROM {q} WHERE emp_id=?", (emp,)
                ).fetchone()
                expected_mgr = int(expected["manager_id"]) if expected["manager_id"] else None
                if row is None or (int(row[0]) if row[0] not in (None, "") else None) != expected_mgr \
                        or int(row[1]) != int(expected["dept_id"]) \
                        or abs(float(row[2]) - float(expected["individual_sales"])) > 1e-5:
                    ok = False
                    break
            if ok:
                matched = True
                break
        assert matched, "No database table contains the loaded sales_data.csv rows"
    finally:
        con.close()


def test_data_correctness():
    data = {}
    children = defaultdict(list)
    with open(INPUT_CSV, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            emp = int(row["emp_id"])
            mgr = int(row["manager_id"]) if row["manager_id"] else None
            dept = int(row["dept_id"])
            sales = float(row["individual_sales"])
            data[emp] = {"mgr": mgr, "dept": dept, "sales": sales, "total": 0}
            if mgr is not None:
                children[mgr].append(emp)

    def get_total(emp):
        total = data[emp]["sales"]
        for child in children[emp]:
            total += get_total(child)
        data[emp]["total"] = total
        return total

    roots = [emp for emp, info in data.items() if info["mgr"] is None]
    for root in roots:
        get_total(root)

    dept_emps = defaultdict(list)
    for emp, info in data.items():
        dept_emps[info["dept"]].append((info["total"], emp))

    expected = {}
    for dept, emps in dept_emps.items():
        emps.sort(key=lambda x: (-x[0], x[1]))
        current_rank = 1
        for i, (total, emp) in enumerate(emps):
            if i > 0 and total < emps[i - 1][0]:
                current_rank = i + 1
            if current_rank <= 3:
                expected[emp] = {
                    "emp_id": emp,
                    "dept_id": dept,
                    "total_team_sales": total,
                    "dept_rank": current_rank,
                }

    actual = []
    with open(OUTPUT_CSV, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            actual.append({
                "emp_id": int(row["emp_id"]),
                "dept_id": int(row["dept_id"]),
                "total_team_sales": float(row["total_team_sales"]),
                "dept_rank": int(row["dept_rank"]),
            })

    assert len(actual) == len(expected), f"Row count mismatch. Expected {len(expected)}, got {len(actual)}"
    ordering = [(row["dept_id"], row["dept_rank"]) for row in actual]
    assert ordering == sorted(ordering), "Rows are not ordered by dept_id then dept_rank"
    assert len({row["emp_id"] for row in actual}) == len(actual), "Output contains duplicate employees"

    for i, act in enumerate(actual):
        assert act["emp_id"] in expected, f"Row {i}: unexpected emp_id {act['emp_id']}"
        exp = expected[act["emp_id"]]
        assert act["dept_id"] == exp["dept_id"], f"Row {i}: dept_id mismatch"
        assert act["dept_rank"] == exp["dept_rank"], f"Row {i}: dept_rank mismatch"
        assert abs(act["total_team_sales"] - exp["total_team_sales"]) < 1e-5, \
            f"Row {i}: total_team_sales mismatch. Expected {exp['total_team_sales']}, got {act['total_team_sales']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
