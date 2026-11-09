#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess

SCRIPT_PATH = "/home/user/get_total_size.sh"
QUERY_PLAN_PATH = "/home/user/query_plan.txt"
DB_PATH = "/home/user/backup.db"


def run_script(name, env=None):
    result = subprocess.run([SCRIPT_PATH, name], capture_output=True, text=True, env=env)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    return result.stdout.strip()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script at {SCRIPT_PATH} is not executable"


def test_script_output_target_dir():
    output = run_script("target_dir")
    assert output == "600", f"Expected output '600' for target_dir, got '{output}'"


def test_script_output_other_dir():
    output = run_script("other_dir")
    assert output == "400", f"Expected output '400' for other_dir, got '{output}'"


def test_script_contents():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read().upper()
    assert "REINDEX" in content, "Script does not contain REINDEX command"
    assert "WITH" in content, "Script does not seem to use a CTE (WITH)"
    assert "SQLITE3" in content, "Script does not seem to invoke sqlite3"


def test_query_plan_exists_and_valid():
    assert os.path.exists(QUERY_PLAN_PATH), f"Query plan missing at {QUERY_PLAN_PATH}"
    with open(QUERY_PLAN_PATH, "r") as f:
        content = f.read().upper()
    assert "SCAN" in content, "query_plan.txt does not appear to contain EXPLAIN QUERY PLAN output"
    assert len(content.strip()) > 0, "query_plan.txt is empty"
    assert "QUERY PLAN" in content, "query_plan.txt is not raw SQLite EXPLAIN QUERY PLAN output"
    assert "RECURSIVE STEP" in content, "query_plan.txt does not show a recursive CTE step"
    assert "SETUP" in content, "query_plan.txt does not show recursive CTE setup"


def strip_sql_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"--[^\n]*", " ", text)
    return text


def test_random_recursive_tree_and_sqlite_pipeline():
    token = secrets.token_hex(10)
    requested_name = "verify_" + token
    child_name = "child_" + token
    grandchild_name = "grandchild_" + token
    greatgrandchild_name = "greatgrandchild_" + token
    decoy_name = "decoy_" + token
    sizes = [secrets.randbelow(900000) + 101 for _ in range(4)]
    expected = sum(sizes)

    backup_path = "/tmp/backup.db.verifier-copy"
    shutil.copy2(DB_PATH, backup_path)

    real_sqlite = "/usr/bin/sqlite3.verifier-real"
    sqlite_path = "/usr/bin/sqlite3"
    count_path = "/tmp/sqlite-verifier-count"
    capture_path = "/tmp/sqlite-verifier-capture"
    for path in (count_path, capture_path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    try:
        con = sqlite3.connect(DB_PATH)
        root_id = con.execute("SELECT id FROM directories WHERE name='root'").fetchone()[0]
        cur = con.execute("INSERT INTO directories(parent_id,name) VALUES (?,?)", (root_id, requested_name))
        requested_id = cur.lastrowid
        cur = con.execute("INSERT INTO directories(parent_id,name) VALUES (?,?)", (requested_id, child_name))
        child_id = cur.lastrowid
        cur = con.execute("INSERT INTO directories(parent_id,name) VALUES (?,?)", (child_id, grandchild_name))
        grandchild_id = cur.lastrowid
        cur = con.execute("INSERT INTO directories(parent_id,name) VALUES (?,?)", (grandchild_id, greatgrandchild_name))
        greatgrandchild_id = cur.lastrowid
        cur = con.execute("INSERT INTO directories(parent_id,name) VALUES (?,?)", (root_id, decoy_name))
        decoy_id = cur.lastrowid

        for index, (dir_id, size) in enumerate(zip(
            (requested_id, child_id, grandchild_id, greatgrandchild_id), sizes
        )):
            con.execute(
                "INSERT INTO files(dir_id,name,size) VALUES (?,?,?)",
                (dir_id, f"random_file_{index}_{token}", size),
            )
        con.execute(
            "INSERT INTO files(dir_id,name,size) VALUES (?,?,?)",
            (decoy_id, "excluded_" + token, expected + 987654),
        )
        con.commit()
        con.close()

        os.rename(sqlite_path, real_sqlite)
        wrapper = f'''#!/bin/bash
set -e
printf '1\\n' >> {count_path}
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat > "$tmp"
{{
  printf '\\n=== SQLITE INVOCATION ===\\n'
  printf '%s\\n' "$@"
  printf '%s\\n' '=== STDIN ==='
  cat "$tmp"
}} >> {capture_path}
exec {real_sqlite} "$@" < "$tmp"
'''
        with open(sqlite_path, "w") as f:
            f.write(wrapper)
        os.chmod(sqlite_path, 0o755)

        output = run_script(requested_name)
        assert re.fullmatch(r"[0-9]+", output), f"Output must contain only an integer, got {output!r}"
        assert output == str(expected), f"Expected dynamic recursive total {expected}, got {output!r}"

        with open(count_path, "r") as f:
            invocation_count = len(f.readlines())
        assert invocation_count == 1, f"Expected one sqlite3 invocation, observed {invocation_count}"

        with open(capture_path, "r") as f:
            captured = strip_sql_comments(f.read())
        upper = captured.upper()
        reindex = re.search(r"(?:^|[;\n])\s*REINDEX(?:\s+[^;\n]+)?\s*;", upper)
        recursive = re.search(r"\bWITH\s+RECURSIVE\b", upper)
        select = re.search(r"\bSELECT\b", upper)
        assert reindex, "The executed sqlite3 input does not contain a REINDEX statement"
        assert recursive, "The executed sqlite3 input does not contain a recursive CTE"
        assert select, "The executed sqlite3 input does not contain a SELECT"
        assert reindex.start() < recursive.start() <= select.start(), \
            "REINDEX must execute before the recursive SELECT in the same sqlite3 invocation"
    finally:
        if os.path.exists(real_sqlite):
            try:
                os.unlink(sqlite_path)
            except FileNotFoundError:
                pass
            os.rename(real_sqlite, sqlite_path)
        if os.path.exists(backup_path):
            shutil.copy2(backup_path, DB_PATH)
            os.unlink(backup_path)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
