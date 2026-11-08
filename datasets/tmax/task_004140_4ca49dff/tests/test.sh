#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import random
import re
import shutil
import sqlite3
import string
import subprocess
import tokenize

import pytest

SCRIPT_PATH = '/home/user/analyze_chains.py'
REPORT_PATH = '/home/user/chain_report.json'
DB_PATH = '/home/user/backups.db'


def run_script():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} exited with status {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )


def get_expected_chains(db_path):
    """
    Derive the expected output directly from the database using a recursive CTE.
    This ensures we match the intent of the rubric regardless of minor data changes.
    """
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    query = """
    WITH RECURSIVE
      chain(root_id, job_id, server_id, size_bytes) AS (
        SELECT job_id, job_id, server_id, size_bytes
        FROM jobs
        WHERE parent_id IS NULL

        UNION ALL

        SELECT c.root_id, j.job_id, j.server_id, j.size_bytes
        FROM jobs j
        JOIN chain c ON j.parent_id = c.job_id
      )
    SELECT
      s.hostname,
      c.root_id,
      SUM(c.size_bytes) as total_size,
      COUNT(c.job_id) as job_count
    FROM chain c
    JOIN servers s ON c.server_id = s.server_id
    GROUP BY c.root_id, s.hostname
    HAVING total_size > 5000
    ORDER BY c.root_id ASC
    """

    c.execute(query)
    rows = c.fetchall()

    expected = {}
    for row in rows:
        hostname = row['hostname']
        if hostname not in expected:
            expected[hostname] = []
        expected[hostname].append({
            'root_job_id': row['root_id'],
            'total_size': row['total_size'],
            'job_count': row['job_count'],
        })

    conn.close()
    return expected


def test_analyzer_exists_and_requests_not_indexed():
    assert os.path.exists(SCRIPT_PATH), f'The required script {SCRIPT_PATH} was not found.'
    assert os.path.isfile(SCRIPT_PATH), f'The path {SCRIPT_PATH} is not a file.'

    with tokenize.open(SCRIPT_PATH) as f:
        source = f.read()
    compile(source, SCRIPT_PATH, 'exec')

    # Remove Python comments so a comment merely mentioning the requirement is not enough.
    tokens = tokenize.generate_tokens(io.StringIO(source).readline)
    uncommented = tokenize.untokenize(
        tok for tok in tokens if tok.type != tokenize.COMMENT
    )
    jobs_not_indexed = re.compile(
        r'\bFROM\s+jobs(?:\s+(?:AS\s+)?[A-Za-z_]\w*)?\s+NOT\s+INDEXED\b',
        re.IGNORECASE,
    )
    assert jobs_not_indexed.search(uncommented), (
        'The analyzer must query the jobs table with SQLite NOT INDEXED.'
    )


def test_execute_analyzer_on_original_database():
    run_script()


def test_chain_report_exists():
    assert os.path.exists(REPORT_PATH), f'The output file {REPORT_PATH} was not found.'
    assert os.path.isfile(REPORT_PATH), f'The path {REPORT_PATH} is not a file.'


def test_chain_report_content():
    assert os.path.exists(REPORT_PATH), f'Cannot verify content, {REPORT_PATH} is missing.'

    with open(REPORT_PATH, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f'The file {REPORT_PATH} does not contain valid JSON. Error: {e}')

    expected_data = get_expected_chains(DB_PATH)

    # Check if the keys (hostnames) match exactly
    assert set(actual_data.keys()) == set(expected_data.keys()), \
        f'Hostnames in report do not match expected. Expected: {list(expected_data.keys())}, Actual: {list(actual_data.keys())}'

    # Check the lists of chains for each hostname
    for hostname, expected_chains in expected_data.items():
        actual_chains = actual_data[hostname]

        assert isinstance(actual_chains, list), f"The value for '{hostname}' must be a list."
        assert len(actual_chains) == len(expected_chains), \
            f"Expected {len(expected_chains)} chains for '{hostname}', but found {len(actual_chains)}."

        # The chains must be sorted by root_job_id in ascending order as per requirements
        for i, (expected_chain, actual_chain) in enumerate(zip(expected_chains, actual_chains)):
            assert actual_chain.get('root_job_id') == expected_chain['root_job_id'], \
                f"Mismatch in root_job_id for '{hostname}' at index {i}. Expected {expected_chain['root_job_id']}, got {actual_chain.get('root_job_id')}."
            assert actual_chain.get('total_size') == expected_chain['total_size'], \
                f"Mismatch in total_size for '{hostname}' chain {expected_chain['root_job_id']}. Expected {expected_chain['total_size']}, got {actual_chain.get('total_size')}."
            assert actual_chain.get('job_count') == expected_chain['job_count'], \
                f"Mismatch in job_count for '{hostname}' chain {expected_chain['root_job_id']}. Expected {expected_chain['job_count']}, got {actual_chain.get('job_count')}."


def remove_db_sidecars(path):
    for suffix in ('', '-wal', '-shm', '-journal'):
        candidate = path + suffix
        if os.path.exists(candidate):
            os.remove(candidate)


def create_stale_index_database(path, servers, jobs):
    """Create idx_parent while empty, detach it, insert rows, then reattach it stale."""
    remove_db_sidecars(path)
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.execute('CREATE TABLE servers (server_id INTEGER PRIMARY KEY, hostname TEXT)')
    cur.execute('CREATE TABLE jobs (job_id INTEGER PRIMARY KEY, server_id INTEGER, parent_id INTEGER, size_bytes INTEGER, type TEXT)')
    cur.execute('CREATE INDEX idx_parent ON jobs(parent_id)')
    rootpage = cur.execute(
        "SELECT rootpage FROM sqlite_master WHERE type='index' AND name='idx_parent'"
    ).fetchone()[0]
    version = cur.execute('PRAGMA schema_version').fetchone()[0]
    cur.execute('PRAGMA writable_schema=ON')
    cur.execute("DELETE FROM sqlite_master WHERE type='index' AND name='idx_parent'")
    cur.execute(f'PRAGMA schema_version={version + 1}')
    conn.commit()
    conn.close()

    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.executemany('INSERT INTO servers VALUES (?, ?)', servers)
    cur.executemany('INSERT INTO jobs VALUES (?, ?, ?, ?, ?)', jobs)
    conn.commit()
    version = cur.execute('PRAGMA schema_version').fetchone()[0]
    cur.execute('PRAGMA writable_schema=ON')
    cur.execute(
        'INSERT INTO sqlite_master(type, name, tbl_name, rootpage, sql) VALUES (?, ?, ?, ?, ?)',
        ('index', 'idx_parent', 'jobs', rootpage, 'CREATE INDEX idx_parent ON jobs(parent_id)'),
    )
    cur.execute(f'PRAGMA schema_version={version + 1}')
    conn.commit()
    conn.close()

    # Confirm this fixture really distinguishes an indexed lookup from a table scan.
    conn = sqlite3.connect(path)
    indexed = conn.execute(
        'SELECT job_id FROM jobs WHERE parent_id IS NULL ORDER BY job_id'
    ).fetchall()
    scanned = conn.execute(
        'SELECT job_id FROM jobs NOT INDEXED WHERE parent_id IS NULL ORDER BY job_id'
    ).fetchall()
    conn.close()
    assert scanned and indexed != scanned, 'Failed to construct the stale-index test fixture.'


def expected_from_rows(servers, jobs):
    hostnames = dict(servers)
    by_parent = {}
    for job_id, server_id, parent_id, size_bytes, job_type in jobs:
        by_parent.setdefault(parent_id, []).append(
            (job_id, server_id, parent_id, size_bytes, job_type)
        )

    result = {}
    roots = sorted(
        (j for j in jobs if j[2] is None and j[4] == 'FULL'),
        key=lambda j: j[0],
    )
    for root in roots:
        stack = [root]
        seen = set()
        total = 0
        count = 0
        while stack:
            job = stack.pop()
            if job[0] in seen:
                continue
            seen.add(job[0])
            total += job[3]
            count += 1
            stack.extend(by_parent.get(job[0], []))
        if total > 5000:
            result.setdefault(hostnames[root[1]], []).append({
                'root_job_id': root[0],
                'total_size': total,
                'job_count': count,
            })
    return result


def test_analyzer_on_unseen_corrupted_databases():
    db_backup = '/tmp/original_backups.db'
    report_backup = '/tmp/original_chain_report.json'
    shutil.copy2(DB_PATH, db_backup)
    had_report = os.path.isfile(REPORT_PATH)
    if had_report:
        shutil.copy2(REPORT_PATH, report_backup)

    try:
        for _ in range(2):
            token = ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(10))
            base = random.SystemRandom().randrange(100, 10000) * 10
            servers = [
                (1, f'alpha-{token}'),
                (2, f'beta-{token}'),
                (3, f'idle-{token}'),
            ]
            jobs = [
                (base + 1, 1, None, 3700, 'FULL'),
                (base + 7, 1, base + 1, 900, 'INC'),
                (base + 3, 1, base + 1, 700, 'INC'),
                (base + 9, 1, base + 3, 250, 'INC'),
                (base + 20, 1, None, 5000, 'FULL'),
                (base + 30, 2, None, 6400, 'FULL'),
                (base + 31, 2, base + 30, 1200, 'INC'),
                (base + 40, 2, None, 1000, 'FULL'),
                (base + 41, 2, base + 40, 4001, 'INC'),
                (base + 50, 3, None, 9999, 'INC'),
                (base + 60, 3, base + 999, 8000, 'INC'),
            ]
            expected = expected_from_rows(servers, jobs)
            create_stale_index_database(DB_PATH, servers, jobs)
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)

            run_script()
            assert os.path.isfile(REPORT_PATH), 'Analyzer did not create chain_report.json.'
            with open(REPORT_PATH, 'r') as f:
                actual = json.load(f)
            assert actual == expected, (
                f'Analyzer produced the wrong report for an unseen database with a stale '
                f'idx_parent index. Expected {expected!r}, got {actual!r}.'
            )
    finally:
        remove_db_sidecars(DB_PATH)
        shutil.copy2(db_backup, DB_PATH)
        if had_report:
            shutil.copy2(report_backup, REPORT_PATH)
        elif os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
