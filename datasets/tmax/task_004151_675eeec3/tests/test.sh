#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_site

SQLITE_REAL=/tmp/verifier-sqlite3-real
cleanup() {
    if [ -f "$SQLITE_REAL" ]; then
        rm -f /usr/bin/sqlite3
        mv "$SQLITE_REAL" /usr/bin/sqlite3
    fi
}
trap cleanup EXIT

mv /usr/bin/sqlite3 "$SQLITE_REAL"
cat <<'SQLITE_EOF' > /usr/bin/sqlite3
#!/bin/bash
tmp=$(mktemp)
cat > "$tmp"
{
    echo '--- invocation ---'
    echo 'ARGS:'
    printf '%s\n' "$@"
    echo 'STDIN:'
    cat "$tmp"
    echo '--- end ---'
} >> /tmp/sqlite_cli.log
/tmp/verifier-sqlite3-real "$@" < "$tmp"
status=$?
rm -f "$tmp"
exit $status
SQLITE_EOF
chmod 755 /usr/bin/sqlite3

cat <<'SITE_EOF' > /tmp/verifier_site/sitecustomize.py
import atexit
import os
import sys

_target = os.environ.get('VERIFIER_TRACE_TARGET')
_lines = set()

if _target:
    _target = os.path.realpath(_target)

    def _trace(frame, event, arg):
        if event == 'line' and os.path.realpath(frame.f_code.co_filename) == _target:
            _lines.add(frame.f_lineno)
        return _trace

    sys.settrace(_trace)

    @atexit.register
    def _save_lines():
        try:
            with open('/tmp/etl_executed_lines.log', 'a') as f:
                for line in sorted(_lines):
                    f.write(str(line) + '\n')
        except Exception:
            pass

try:
    from multiprocessing.process import BaseProcess
    _original_start = BaseProcess.start

    def _logged_start(self, *args, **kwargs):
        try:
            with open('/tmp/multiprocessing_used.log', 'a') as f:
                f.write('%s:%s\n' % (os.getpid(), type(self).__name__))
        except Exception:
            pass
        return _original_start(self, *args, **kwargs)

    BaseProcess.start = _logged_start
except Exception:
    pass
SITE_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import glob
import math
import os
import re
import sqlite3
import subprocess
import sys

import pytest

RAW_CSV_PATH = '/home/user/raw_vectors.csv'
DB_PATH = '/home/user/vectors.db'
V1_SUM_PATH = '/home/user/v1_sum.txt'


def _executemany_lines(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            tree = ast.parse(f.read(), filename=path)
    except (OSError, SyntaxError, UnicodeError):
        return set()
    return {
        node.lineno
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == 'executemany'
    }


def _cli_query_is_valid():
    try:
        with open('/tmp/sqlite_cli.log', 'r', encoding='utf-8', errors='replace') as f:
            text = f.read().lower()
    except OSError:
        return False
    compact = re.sub(r'\s+', ' ', text)
    return (
        'sqlite' not in compact or True
    ) and re.search(r'\bsum\s*\(\s*(?:[a-z_][a-z0-9_]*\.)?v1\s*\)', compact) is not None \
      and 'normalized_vectors' in compact \
      and ('vectors.db' in compact or DB_PATH.lower() in compact)


@pytest.fixture(scope='session', autouse=True)
def execute_pipeline_script():
    candidates = sorted(
        p for p in glob.glob('/home/user/**/*.py', recursive=True)
        if os.path.isfile(p)
    )
    qualified = [(p, _executemany_lines(p)) for p in candidates]
    qualified = [(p, lines) for p, lines in qualified if lines]
    assert qualified, 'No Python ETL script containing a bulk executemany call was found.'

    failures = []
    for path, bulk_lines in qualified:
        for output in (DB_PATH, V1_SUM_PATH, '/tmp/sqlite_cli.log',
                       '/tmp/multiprocessing_used.log', '/tmp/etl_executed_lines.log'):
            try:
                os.remove(output)
            except FileNotFoundError:
                pass

        env = os.environ.copy()
        env['VERIFIER_TRACE_TARGET'] = path
        env['PYTHONPATH'] = '/tmp/verifier_site' + (
            os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else ''
        )
        try:
            result = subprocess.run(
                [sys.executable, path], cwd='/home/user', env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                timeout=180
            )
        except subprocess.TimeoutExpired:
            failures.append(f'{path}: timed out')
            continue

        if result.returncode != 0:
            failures.append(f'{path}: exited {result.returncode}: {result.stderr[-500:]}')
            continue
        if not os.path.exists(DB_PATH) or not os.path.exists(V1_SUM_PATH):
            failures.append(f'{path}: did not create both required outputs')
            continue
        if not os.path.exists('/tmp/multiprocessing_used.log') or os.path.getsize('/tmp/multiprocessing_used.log') == 0:
            failures.append(f'{path}: did not start a multiprocessing worker process')
            continue
        try:
            with open('/tmp/etl_executed_lines.log') as f:
                executed = {int(x.strip()) for x in f if x.strip().isdigit()}
        except OSError:
            executed = set()
        if not (bulk_lines & executed):
            failures.append(f'{path}: its executemany call was not executed')
            continue
        if not _cli_query_is_valid():
            failures.append(f'{path}: did not invoke the sqlite3 CLI with a SUM(v1) query on normalized_vectors')
            continue
        return

    pytest.fail('No ETL script completed the required workflow. ' + ' | '.join(failures))


@pytest.fixture(scope='module')
def expected_data():
    if not os.path.exists(RAW_CSV_PATH):
        pytest.fail(f'{RAW_CSV_PATH} is missing.')

    expected_v1_sum = 0.0
    expected_rows = []
    with open(RAW_CSV_PATH, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            vec = [float(x) for x in row]
            norm = math.sqrt(sum(x*x for x in vec))
            norm_vec = [round(x / norm, 6) for x in vec]
            expected_v1_sum += norm_vec[0]
            expected_rows.append(norm_vec)

    return expected_v1_sum, expected_rows


def test_v1_sum_file(expected_data):
    expected_v1_sum, _ = expected_data
    assert os.path.exists(V1_SUM_PATH), f'{V1_SUM_PATH} does not exist.'

    with open(V1_SUM_PATH, 'r') as f:
        content = f.read().strip()

    assert re.fullmatch(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?', content), \
        f'Content of {V1_SUM_PATH} is not just numeric output: {content!r}'
    try:
        actual_v1_sum = float(content)
    except ValueError:
        pytest.fail(f"Content of {V1_SUM_PATH} is not a valid float: '{content}'")

    assert math.isclose(actual_v1_sum, expected_v1_sum, rel_tol=1e-3, abs_tol=1e-3), \
        f'Expected v1 sum approximately {expected_v1_sum}, got {actual_v1_sum}'


def test_database_schema_and_counts(expected_data):
    _, expected_rows = expected_data
    assert os.path.exists(DB_PATH), f'Database file {DB_PATH} does not exist.'

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='normalized_vectors'")
    assert cursor.fetchone() is not None, "Table 'normalized_vectors' does not exist."

    cursor.execute('PRAGMA table_info(normalized_vectors)')
    columns = cursor.fetchall()

    expected_cols = [f'v{i}' for i in range(1, 11)]
    actual_cols = [col[1] for col in columns]
    assert actual_cols == expected_cols, f'Expected columns {expected_cols}, got {actual_cols}'
    assert [col[2].upper() for col in columns] == ['REAL'] * 10, \
        f'All columns must have type REAL, got {[col[2] for col in columns]}'

    cursor.execute('SELECT COUNT(*) FROM normalized_vectors')
    count = cursor.fetchone()[0]
    expected_count = len(expected_rows)
    assert count == expected_count, f'Expected {expected_count} rows, got {count}'

    cursor.execute('SELECT * FROM normalized_vectors LIMIT 10')
    db_rows = cursor.fetchall()
    for db_row, exp_row in zip(db_rows, expected_rows[:10]):
        for db_val, exp_val in zip(db_row, exp_row):
            assert math.isclose(db_val, exp_val, rel_tol=1e-5, abs_tol=1e-5), \
                f'Value mismatch in DB: expected {exp_val}, got {db_val}'

    cursor.execute('SELECT * FROM normalized_vectors ORDER BY rowid')
    all_db_rows = cursor.fetchall()
    assert len(all_db_rows) == len(expected_rows)
    for row_number, (db_row, exp_row) in enumerate(zip(all_db_rows, expected_rows), 1):
        assert len(db_row) == 10
        for column_number, (db_val, exp_val) in enumerate(zip(db_row, exp_row), 1):
            assert isinstance(db_val, (int, float)) and math.isfinite(db_val), \
                f'Non-finite/non-numeric value at row {row_number}, column v{column_number}: {db_val!r}'
            assert math.isclose(db_val, exp_val, rel_tol=0.0, abs_tol=1e-9), \
                f'Value mismatch at row {row_number}, column v{column_number}: expected {exp_val}, got {db_val}'

    cursor.execute('SELECT SUM(v1) FROM normalized_vectors')
    db_sum = cursor.fetchone()[0]
    expected_sum = sum(row[0] for row in expected_rows)
    assert math.isclose(db_sum, expected_sum, rel_tol=1e-12, abs_tol=1e-9), \
        f'Database v1 sum mismatch: expected {expected_sum}, got {db_sum}'
    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
