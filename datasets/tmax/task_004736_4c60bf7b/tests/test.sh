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

DB_PATH = '/home/user/audit_logs.db'
LOG_PATH = '/home/user/suspicious_users.log'
CPP_PATH = '/home/user/audit_analyzer.cpp'
BIN_PATH = '/home/user/audit_analyzer'


def expected_lines(context):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute('''
            WITH rolling AS (
                SELECT actor, SUM(risk) OVER (
                    PARTITION BY actor
                    ORDER BY action_time
                    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
                ) AS rolling_risk
                FROM system_access
                WHERE context_tag = ?
            )
            SELECT actor, MAX(rolling_risk) AS max_risk
            FROM rolling
            GROUP BY actor
            ORDER BY max_risk DESC, actor ASC
            LIMIT 5
        ''', (context,)).fetchall()
    finally:
        conn.close()
    return [f"Actor: {actor}, Max Rolling Risk: {score:.2f}" for actor, score in rows]


def actual_lines():
    assert os.path.exists(LOG_PATH), f"Log file missing at {LOG_PATH}"
    assert os.path.isfile(LOG_PATH), f"Path {LOG_PATH} exists but is not a file"
    with open(LOG_PATH, 'r') as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def run_analyzer(context):
    result = subprocess.run(
        [BIN_PATH, context], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"Analyzer failed for context {context!r} with exit code {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert actual_lines() == expected_lines(context)


def test_cpp_file_exists():
    assert os.path.exists(CPP_PATH), f"C++ source file missing at {CPP_PATH}"
    assert os.path.isfile(CPP_PATH), f"Path {CPP_PATH} exists but is not a file"


def test_log_file_exists():
    assert os.path.exists(LOG_PATH), f"Log file missing at {LOG_PATH}"
    assert os.path.isfile(LOG_PATH), f"Path {LOG_PATH} exists but is not a file"


def test_source_uses_required_sqlite_features():
    with open(CPP_PATH, 'r', errors='replace') as f:
        source = f.read()
    assert re.search(r'\bsqlite3_open(?:_v2)?\s*\(', source), "Program must open the database with the sqlite3 C API"
    assert re.search(r'\bsqlite3_prepare(?:_v2|_v3)?\s*\(', source), "Program must prepare its SQL with the sqlite3 C API"
    assert re.search(r'\bsqlite3_bind_text\s*\(', source), "Context tag must be bound as a SQL parameter"
    assert re.search(r'\bOVER\b', source, re.IGNORECASE), "SQL query must use a window function"


def test_program_compiles_runs_and_enforces_one_argument():
    build = subprocess.run(
        ['g++', '-std=c++17', CPP_PATH, '-lsqlite3', '-o', BIN_PATH],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, f"C++ program did not compile:\n{build.stdout}\n{build.stderr}"

    no_arg = subprocess.run([BIN_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert no_arg.returncode != 0, "Analyzer must reject invocation with no context argument"
    two_args = subprocess.run([BIN_PATH, 'PROD', 'DEV'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert two_args.returncode != 0, "Analyzer must reject invocation with more than one context argument"

    run_analyzer('PROD')


def test_log_file_contents():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''
        WITH rolling AS (
            SELECT actor, SUM(risk) OVER (
                PARTITION BY actor
                ORDER BY action_time
                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
            ) as rolling_risk
            FROM system_access
            WHERE context_tag = 'PROD'
        )
        SELECT actor, MAX(rolling_risk) as max_risk
        FROM rolling
        GROUP BY actor
        ORDER BY max_risk DESC, actor ASC
        LIMIT 5;
    ''')
    rows = c.fetchall()
    conn.close()

    expected = [f"Actor: {row[0]}, Max Rolling Risk: {row[1]:.2f}" for row in rows]
    actual = actual_lines()
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} lines in the log file, but found {len(actual)}."
    )
    for i, (got, wanted) in enumerate(zip(actual, expected)):
        assert got == wanted, (
            f"Line {i+1} mismatch.\nExpected: '{wanted}'\nActual:   '{got}'"
        )


def test_analyzer_on_unpredictable_database_and_contexts():
    backup = '/tmp/audit_logs.verifier_backup.db'
    shutil.copy2(DB_PATH, backup)
    random_context = "CTX_" + secrets.token_hex(8) + "'--?"
    contexts = ['PROD', 'DEV', random_context]

    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute('DELETE FROM system_access')
        rows = []
        event_id = 1
        for context_index, context in enumerate(contexts):
            for actor_index in range(7):
                actor = f'user_{context_index}_{actor_index}_{secrets.token_hex(3)}'
                for event_index in range(5):
                    risk = (secrets.randbelow(76) + 1) / 4.0
                    action_time = 100000 * context_index + 1000 * actor_index + 10 * event_index
                    rows.append((
                        event_id, actor, f'target_{secrets.token_hex(2)}',
                        action_time, risk, context
                    ))
                    event_id += 1
        conn.executemany('INSERT INTO system_access VALUES (?,?,?,?,?,?)', rows)
        conn.commit()
        conn.close()

        for context in contexts:
            run_analyzer(context)
    finally:
        if os.path.exists(backup):
            os.replace(backup, DB_PATH)
        if os.path.exists(BIN_PATH):
            subprocess.run([BIN_PATH, 'PROD'], cwd='/home/user', timeout=10,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
