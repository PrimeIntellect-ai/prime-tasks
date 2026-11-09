#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile


def test_planner_executable_exists():
    assert os.path.exists('/home/user/planner'), "The executable /home/user/planner does not exist. Did you compile it?"
    assert os.access('/home/user/planner', os.X_OK), "The file /home/user/planner is not executable."


def test_planner_output_bkp_005():
    try:
        result = subprocess.run(['/home/user/planner', 'bkp_005'], capture_output=True, text=True, timeout=5)
    except Exception as e:
        assert False, f"Failed to run /home/user/planner: {e}"

    output = result.stdout.strip()

    expected_path_pattern = r"Path:\s*bkp_001\s*->\s*bkp_002\s*->\s*bkp_003\s*->\s*bkp_004\s*->\s*bkp_005"
    expected_size_pattern = r"Total Size:\s*136314880"

    assert re.search(expected_path_pattern, output), f"Output did not contain the expected path for bkp_005. Output was:\n{output}"
    assert re.search(expected_size_pattern, output), f"Output did not contain the expected total size for bkp_005. Output was:\n{output}"


def test_planner_output_bkp_003():
    try:
        result = subprocess.run(['/home/user/planner', 'bkp_003'], capture_output=True, text=True, timeout=5)
    except Exception as e:
        assert False, f"Failed to run /home/user/planner: {e}"

    output = result.stdout.strip()

    expected_path_pattern = r"Path:\s*bkp_001\s*->\s*bkp_002\s*->\s*bkp_003"
    expected_size_pattern = r"Total Size:\s*125829120"

    assert re.search(expected_path_pattern, output), f"Output did not contain the expected path for bkp_003. Output was:\n{output}"
    assert re.search(expected_size_pattern, output), f"Output did not contain the expected total size for bkp_003. Output was:\n{output}"


def test_optimize_sql():
    sql_file = '/home/user/optimize.sql'
    assert os.path.exists(sql_file), f"The file {sql_file} does not exist."

    with open(sql_file, 'r') as f:
        content = f.read().lower()

    # Check for CREATE INDEX ... ON backup_lineage
    assert "create " in content and "index " in content, f"{sql_file} does not contain a CREATE INDEX statement."
    assert "backup_lineage" in content, f"{sql_file} does not mention the backup_lineage table."
    assert "child_id" in content, f"{sql_file} does not index the child_id column, which is necessary for fast parent lookups."


def compile_and_check_source():
    source = '/home/user/planner.c'
    assert os.path.isfile(source), "The required C source file /home/user/planner.c does not exist."

    output = '/tmp/planner_from_source'
    result = subprocess.run(
        ['gcc', source, '-o', output, '-lsqlite3'],
        capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"planner.c did not compile with SQLite3:\n{result.stderr}"

    symbols = subprocess.run(
        ['nm', '-D', output], capture_output=True, text=True, timeout=5, check=True
    ).stdout
    assert re.search(r'\bsqlite3_open(?:_v2)?\b', symbols), "planner.c does not use sqlite3_open/sqlite3_open_v2."
    uses_exec = re.search(r'\bsqlite3_exec\b', symbols)
    uses_prepared_query = re.search(r'\bsqlite3_prepare_v2\b', symbols) and re.search(r'\bsqlite3_step\b', symbols)
    assert uses_exec or uses_prepared_query, "planner.c does not execute a query through the SQLite3 C API."
    return output


def test_planner_source_exists_compiles_and_uses_sqlite_api():
    compile_and_check_source()


def assert_exact_plan(executable, target, expected_path, expected_total):
    result = subprocess.run([executable, target], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, f"{executable} exited with {result.returncode}:\n{result.stderr}"

    path_match = re.search(r'^Path:\s*(.*?)\s*$', result.stdout, re.MULTILINE)
    total_match = re.search(r'^Total Size:\s*([0-9]+)\s*$', result.stdout, re.MULTILINE)
    assert path_match, f"No valid Path line in output from {executable}:\n{result.stdout}"
    assert total_match, f"No valid Total Size line in output from {executable}:\n{result.stdout}"

    actual_path = [part.strip() for part in path_match.group(1).split('->')]
    assert actual_path == expected_path, f"Wrong dynamically generated path from {executable}: {actual_path}"
    assert int(total_match.group(1)) == expected_total, f"Wrong dynamically generated total from {executable}."


def test_planner_queries_database_and_traverses_unseen_lineage():
    compiled_source = compile_and_check_source()
    db_path = '/home/user/backups.db'
    backup_path = '/tmp/backups.db.verifier-backup'
    shutil.copy2(db_path, backup_path)

    token = str(secrets.randbelow(90000000) + 10000000)
    ids = [f'bkp_{token}_{i}' for i in range(4)]
    sizes = [secrets.randbelow(9000000) + 1001 for _ in ids]

    try:
        conn = sqlite3.connect(db_path)
        try:
            conn.executemany(
                'INSERT INTO backup_metadata(backup_id, backup_type, size_bytes) VALUES (?, ?, ?)',
                [(ids[0], 'full', sizes[0])] + [(x, 'incremental', size) for x, size in zip(ids[1:], sizes[1:])]
            )
            conn.executemany(
                'INSERT INTO backup_lineage(parent_id, child_id) VALUES (?, ?)',
                list(zip(ids[:-1], ids[1:]))
            )
            conn.commit()
        finally:
            conn.close()

        expected_total = sum(sizes)
        assert_exact_plan('/home/user/planner', ids[-1], ids, expected_total)
        assert_exact_plan(compiled_source, ids[-1], ids, expected_total)
    finally:
        for suffix in ('-wal', '-shm'):
            try:
                os.remove(db_path + suffix)
            except FileNotFoundError:
                pass
        os.replace(backup_path, db_path)


def test_optimize_sql_executes_and_builds_child_lookup_index():
    sql_file = '/home/user/optimize.sql'
    assert os.path.isfile(sql_file), f"The file {sql_file} does not exist."
    with open(sql_file, 'r') as f:
        sql = f.read()

    fd, db_path = tempfile.mkstemp(prefix='optimize-check-', suffix='.db')
    os.close(fd)
    try:
        conn = sqlite3.connect(db_path)
        try:
            conn.executescript('''
                CREATE TABLE backup_metadata (
                    backup_id TEXT PRIMARY KEY,
                    backup_type TEXT,
                    size_bytes INTEGER
                );
                CREATE TABLE backup_lineage (
                    parent_id TEXT,
                    child_id TEXT
                );
            ''')
            conn.set_progress_handler(lambda: 1, 1000000)
            try:
                conn.executescript(sql)
            except sqlite3.Error as e:
                assert False, f"optimize.sql could not be executed by SQLite: {e}"
            finally:
                conn.set_progress_handler(None, 0)

            indexes = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='backup_lineage' AND name NOT LIKE 'sqlite_autoindex_%'"
            ).fetchall()
            suitable = False
            for (name,) in indexes:
                columns = [row[0] for row in conn.execute(
                    'SELECT name FROM pragma_index_info(?) ORDER BY seqno', (name,)
                )]
                if columns and columns[0].lower() == 'child_id':
                    suitable = True
                    break
            assert suitable, "optimize.sql did not create an index on backup_lineage with child_id as its leading column."
        finally:
            conn.close()
    finally:
        os.remove(db_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
