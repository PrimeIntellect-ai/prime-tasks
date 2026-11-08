#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_recovery.py
import json
import os
import random
import re
import secrets
import sqlite3
import subprocess
import sys
import tempfile

DB_PATH = '/home/user/legacy_backup.db'
TARGET_PATH = '/home/user/target_users.json'
SCRIPT_PATH = '/home/user/recover_data.py'
REPORT_PATH = '/home/user/recovery_report.json'


def create_database(shards, rows, targets):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        for shard in shards:
            cur.execute(f'CREATE TABLE "{shard}" (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL, status TEXT)')
            cur.execute(f'CREATE INDEX "idx_status_{shard}" ON "{shard}"(status)')
        for shard, user_id, amount, status in rows:
            cur.execute(f'INSERT INTO "{shard}" (user_id, amount, status) VALUES (?, ?, ?)',
                        (user_id, amount, status))
        cur.execute('CREATE TABLE system_logs (id INTEGER PRIMARY KEY, message TEXT)')
        cur.execute("INSERT INTO system_logs(message) VALUES ('not sales data')")
        conn.commit()
    finally:
        conn.close()
    with open(TARGET_PATH, 'w') as f:
        json.dump(targets, f)


def expected_for(rows, targets):
    result = {str(uid): {'total_amount': 0.0, 'transaction_count': 0} for uid in targets}
    target_set = set(targets)
    for _, uid, amount, status in rows:
        if uid in target_set and status == 'COMPLETED':
            result[str(uid)]['total_amount'] += float(amount)
            result[str(uid)]['transaction_count'] += 1
    return result


def install_tracer(directory):
    sitecustomize = r'''
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_log_path = os.environ.get("RECOVERY_SQL_TRACE")

class TracedConnection(sqlite3.Connection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        sqlite3.Connection.set_trace_callback(self, self._record_sql)

    def _record_sql(self, statement):
        if _log_path:
            with open(_log_path, "a", encoding="utf-8") as out:
                out.write(json.dumps(statement) + "\\n")

    def set_trace_callback(self, callback):
        # Preserve verifier tracing even if application code installs a callback.
        sqlite3.Connection.set_trace_callback(self, self._record_sql)


def traced_connect(*args, **kwargs):
    kwargs["factory"] = TracedConnection
    return _real_connect(*args, **kwargs)

sqlite3.connect = traced_connect
'''
    with open(os.path.join(directory, 'sitecustomize.py'), 'w') as f:
        f.write(sitecustomize)


def run_script_and_read_trace(shards):
    assert os.path.exists(SCRIPT_PATH), f'Python script {SCRIPT_PATH} is missing.'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a file.'

    with open(SCRIPT_PATH, 'r') as f:
        content = f.read().upper()
    # Retain the original source assertion in addition to runtime validation.
    assert 'NOT INDEXED' in content, "The script does not contain the required 'NOT INDEXED' clause."

    if os.path.lexists(REPORT_PATH):
        if os.path.isdir(REPORT_PATH):
            raise AssertionError(f'{REPORT_PATH} must be a file.')
        os.remove(REPORT_PATH)

    with tempfile.TemporaryDirectory() as trace_dir:
        install_tracer(trace_dir)
        trace_path = os.path.join(trace_dir, 'sql.jsonl')
        env = os.environ.copy()
        old_path = env.get('PYTHONPATH')
        env['PYTHONPATH'] = trace_dir if not old_path else trace_dir + os.pathsep + old_path
        env['RECOVERY_SQL_TRACE'] = trace_path
        completed = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd='/home/user', env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert completed.returncode == 0, (
            f'{SCRIPT_PATH} failed with exit code {completed.returncode}. '
            f'stderr: {completed.stderr[-2000:]}'
        )
        assert os.path.exists(trace_path), 'No SQLite statements were observed while executing the script.'
        statements = []
        with open(trace_path, 'r', encoding='utf-8') as f:
            for line in f:
                if line.strip():
                    statements.append(json.loads(line))

    assert os.path.exists(REPORT_PATH), f'Output file {REPORT_PATH} is missing.'
    assert os.path.isfile(REPORT_PATH), f'{REPORT_PATH} is not a file.'

    selects = [s for s in statements if re.match(r'^\s*(?:--[^\n]*\n\s*)*SELECT\b', s, re.I)]
    for shard in shards:
        ident = re.escape(shard)
        table_ref = re.compile(
            r'\b(?:FROM|JOIN)\s+(?:(?:main|temp)\s*\.\s*)?'
            r'(?:"' + ident + r'"|`' + ident + r'`|\[' + ident + r'\]|' + ident + r')\b?',
            re.I
        )
        references = []
        for statement in selects:
            references.extend((statement, match.end()) for match in table_ref.finditer(statement))
        assert references, f'No executed SELECT queried required shard {shard!r}.'
        for statement, end in references:
            tail = statement[end:]
            # SQLite permits either no alias, AS alias, or a bare alias before NOT INDEXED.
            clause = re.match(
                r'\s*(?:(?:AS\s+)?(?!NOT\b)[A-Za-z_][A-Za-z0-9_]*\s+)?NOT\s+INDEXED\b',
                tail, re.I
            )
            assert clause, f'Executed query against {shard!r} did not apply NOT INDEXED: {statement}'


def validate_report(expected):
    try:
        with open(REPORT_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{REPORT_PATH} does not contain valid JSON: {exc}')

    assert isinstance(data, dict), f'Expected the root of {REPORT_PATH} to be a JSON object.'
    assert set(data) == set(expected), 'The report keys must exactly match the target user IDs.'
    for user_id, stats in expected.items():
        assert user_id in data, f"Missing user_id '{user_id}' in the recovery report."
        user_data = data[user_id]
        assert isinstance(user_data, dict), f'Report value for user {user_id} must be an object.'
        assert 'total_amount' in user_data, f"Missing 'total_amount' for user {user_id}."
        assert 'transaction_count' in user_data, f"Missing 'transaction_count' for user {user_id}."
        assert isinstance(user_data['transaction_count'], int), f"'transaction_count' for user {user_id} must be an integer."
        assert isinstance(user_data['total_amount'], (int, float)), f"'total_amount' for user {user_id} must be a number."
        assert abs(user_data['total_amount'] - stats['total_amount']) < 0.01, (
            f"Incorrect 'total_amount' for user {user_id}. Expected {stats['total_amount']}, got {user_data['total_amount']}."
        )
        assert user_data['transaction_count'] == stats['transaction_count'], (
            f"Incorrect 'transaction_count' for user {user_id}. Expected {stats['transaction_count']}, got {user_data['transaction_count']}."
        )


def main():
    baseline_shards = ['sales_na', 'sales_eu', 'sales_apac']
    baseline_rows = [
        ('sales_na', 101, 50.0, 'COMPLETED'),
        ('sales_na', 101, 100.5, 'COMPLETED'),
        ('sales_na', 102, 20.0, 'FAILED'),
        ('sales_na', 204, 30.0, 'COMPLETED'),
        ('sales_eu', 101, 200.0, 'COMPLETED'),
        ('sales_eu', 105, 10.0, 'COMPLETED'),
        ('sales_eu', 204, 40.0, 'PENDING'),
        ('sales_apac', 105, 500.0, 'COMPLETED'),
        ('sales_apac', 101, 10.0, 'FAILED'),
        ('sales_apac', 999, 99.9, 'COMPLETED'),
    ]
    baseline_targets = [101, 105, 204, 300]
    create_database(baseline_shards, baseline_rows, baseline_targets)
    run_script_and_read_trace(baseline_shards)
    validate_report(expected_for(baseline_rows, baseline_targets))

    token = secrets.token_hex(4)
    rng = random.SystemRandom()
    shards = [f'sales_north_{token}', f'sales_south_{token}', f'sales_special_{token}']
    targets = [rng.randrange(10000, 90000) for _ in range(4)]
    while len(set(targets)) != 4:
        targets = [rng.randrange(10000, 90000) for _ in range(4)]
    outsider = rng.randrange(90001, 99999)
    rows = [
        (shards[0], targets[0], 11.25 + rng.randrange(1, 100), 'COMPLETED'),
        (shards[1], targets[0], 0.5 + rng.randrange(1, 100), 'COMPLETED'),
        (shards[2], targets[0], 999.0, 'FAILED'),
        (shards[0], targets[1], 5.75 + rng.randrange(1, 50), 'COMPLETED'),
        (shards[1], targets[1], 123.0, 'PENDING'),
        (shards[2], targets[2], 7.5 + rng.randrange(1, 80), 'COMPLETED'),
        (shards[2], targets[2], 3.25 + rng.randrange(1, 80), 'COMPLETED'),
        (shards[1], outsider, 876.54, 'COMPLETED'),
        (shards[0], targets[3], 444.0, 'completed'),
    ]
    create_database(shards, rows, targets)
    run_script_and_read_trace(shards)
    validate_report(expected_for(rows, targets))


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_recovery.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
