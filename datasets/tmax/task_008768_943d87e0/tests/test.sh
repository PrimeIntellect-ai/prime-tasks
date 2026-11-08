#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gc
import hashlib
import os
import re
import runpy
import shutil
import sqlite3
import stat
import tempfile
import pytest

DB_PATH = '/home/user/research_data.db'
SCRIPT_PATH = '/home/user/analyze.py'
OUTPUT_PATH = '/home/user/top_type.txt'


def test_top_type_file_exists_and_correct():
    """Check if top_type.txt exists and contains the correct entity type."""
    file_path = OUTPUT_PATH
    assert os.path.exists(file_path), f"Output file missing at {file_path}"
    assert os.path.isfile(file_path), f"{file_path} is not a file"

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == "Metabolite", f"Expected 'Metabolite', but found '{content}'"


def test_analyze_script_exists():
    """Check if the analyze.py script was created."""
    script_path = SCRIPT_PATH
    assert os.path.exists(script_path), f"Script missing at {script_path}"
    assert os.path.isfile(script_path), f"{script_path} is not a file"
    assert stat.S_ISREG(os.stat(script_path).st_mode), f"{script_path} is not a regular file"


def test_analyze_script_bypasses_index():
    """Check if the script contains logic to bypass the index."""
    script_path = SCRIPT_PATH
    if not os.path.exists(script_path):
        pytest.fail("analyze.py script is missing, cannot check for index bypass.")

    with open(script_path, 'r') as f:
        content = f.read().lower()

    # Preserve the original source-level assertion.
    bypassed = "not indexed" in content or "indexed by" in content or "+src" in content or "+ src" in content
    assert bypassed, "The script does not appear to explicitly bypass the index (e.g., using 'NOT INDEXED')."


class CursorProxy:
    def __init__(self, cursor, records):
        self._cursor = cursor
        self._records = records

    def execute(self, sql, parameters=()):
        text = str(sql)
        plan = None
        if re.search(r'\b(select|with)\b', text, re.I):
            try:
                plan = list(self._cursor.connection.execute('EXPLAIN QUERY PLAN ' + text, parameters))
            except Exception:
                plan = None
            self._records.append((text, plan))
        self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        self._cursor.executemany(sql, seq_of_parameters)
        return self

    def executescript(self, sql_script):
        self._cursor.executescript(sql_script)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class ConnectionProxy:
    def __init__(self, connection, records):
        self._connection = connection
        self._records = records

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs), self._records)

    def execute(self, sql, parameters=()):
        return self.cursor().execute(sql, parameters)

    def executemany(self, sql, seq_of_parameters):
        return self.cursor().executemany(sql, seq_of_parameters)

    def executescript(self, sql_script):
        return self.cursor().executescript(sql_script)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return self._connection.__exit__(exc_type, exc_value, traceback)

    def __getattr__(self, name):
        return getattr(self._connection, name)


def file_hash(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(65536), b''):
            h.update(block)
    return h.hexdigest()


def trusted_top_type():
    conn = sqlite3.connect(DB_PATH)
    try:
        row = conn.execute('''
            WITH ranked AS (
                SELECT src, dst, weight,
                       ROW_NUMBER() OVER (
                           PARTITION BY src, dst
                           ORDER BY timestamp DESC
                       ) AS rn
                FROM relations NOT INDEXED
            ), averages AS (
                SELECT e.entity_type AS entity_type, AVG(r.weight) AS avg_weight
                FROM ranked AS r
                JOIN entities AS e ON e.id = r.src
                WHERE r.rn = 1
                GROUP BY e.entity_type
            )
            SELECT entity_type
            FROM averages
            ORDER BY avg_weight DESC, entity_type ASC
            LIMIT 1
        ''').fetchone()
        assert row is not None, 'Trusted computation found no active edges'
        return row[0]
    finally:
        conn.close()


def run_submission():
    records = []
    real_connect = sqlite3.connect

    def monitored_connect(*args, **kwargs):
        return ConnectionProxy(real_connect(*args, **kwargs), records)

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    sqlite3.connect = monitored_connect
    try:
        try:
            runpy.run_path(SCRIPT_PATH, run_name='__main__')
        except SystemExit as exc:
            assert exc.code in (None, 0), f'analyze.py exited unsuccessfully with status {exc.code}'
    finally:
        sqlite3.connect = real_connect
        gc.collect()

    assert os.path.isfile(OUTPUT_PATH), 'Executing analyze.py did not create top_type.txt'
    with open(OUTPUT_PATH, 'r') as f:
        result = f.read().strip()

    normalized_records = []
    for sql, plan in records:
        normalized = sql.lower().replace('"', '').replace('`', '').replace('[', '').replace(']', '')
        if re.search(r'\b(from|join)\s+relations\b', normalized):
            normalized_records.append((sql, normalized, plan))

    assert normalized_records, 'analyze.py did not execute a SELECT that reads the relations table'
    for sql, normalized, plan in normalized_records:
        explicit_bypass = ('not indexed' in normalized or
                           re.search(r'\+\s*(?:\w+\.)?src\b', normalized) is not None)
        assert explicit_bypass, f'Relations query does not explicitly bypass idx_rel_src: {sql}'
        assert plan is not None, f'Could not inspect the query plan for relations query: {sql}'
        details = ' '.join(str(row[3]) for row in plan).lower()
        assert 'idx_rel_src' not in details, f'Query plan uses corrupted idx_rel_src: {details}'

    return result


def test_script_execution_graph_analysis_and_query_plan():
    backup_fd, backup_path = tempfile.mkstemp(prefix='research_data_', suffix='.db')
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)
    old_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, 'rb') as f:
            old_output = f.read()

    try:
        # First exercise the shipped database and preserve the original expected result.
        assert trusted_top_type() == 'Metabolite'
        before = file_hash(DB_PATH)
        assert run_submission() == trusted_top_type()
        assert file_hash(DB_PATH) == before, 'analyze.py modified the database'

        # Change the data so that Protein is the winner; the expected answer is
        # independently recomputed rather than embedded in the test.
        conn = sqlite3.connect(DB_PATH)
        conn.execute('UPDATE relations SET weight = CASE WHEN src IN (1, 2) THEN 100.0 ELSE 1.0 END')
        conn.commit()
        conn.close()
        expected = trusted_top_type()
        assert expected == 'Protein'
        before = file_hash(DB_PATH)
        assert run_submission() == expected
        assert file_hash(DB_PATH) == before, 'analyze.py modified the database'

        # Exercise another winner to rule out a two-value or fixed-answer script.
        conn = sqlite3.connect(DB_PATH)
        conn.execute('UPDATE relations SET weight = CASE WHEN src IN (3, 4) THEN 200.0 ELSE 1.0 END')
        conn.commit()
        conn.close()
        expected = trusted_top_type()
        assert expected == 'Gene'
        before = file_hash(DB_PATH)
        assert run_submission() == expected
        assert file_hash(DB_PATH) == before, 'analyze.py modified the database'
    finally:
        gc.collect()
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
        if old_output is None:
            if os.path.lexists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, 'wb') as f:
                f.write(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
