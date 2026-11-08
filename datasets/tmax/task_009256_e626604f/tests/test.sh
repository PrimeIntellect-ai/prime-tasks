#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid

import pytest

SCRIPT_PATH = '/home/user/etl_pipeline.py'
OUTPUT_PATH = '/home/user/output/key_communicators.json'
DB_PATH = '/home/user/data/comms.db'
AUDIT_DIR = '/tmp/etl_audit'
SQL_LOG = '/tmp/etl_sql.log'
NX_LOG = '/tmp/etl_networkx.log'

SITE_CUSTOMIZE = r'''
import json
import sqlite3

_real_connect = sqlite3.connect

def _audited_connect(*args, **kwargs):
    conn = _real_connect(*args, **kwargs)
    def trace(statement):
        try:
            with open('/tmp/etl_sql.log', 'a') as f:
                f.write(statement.replace('\\x00', '') + '\\n--STATEMENT--\\n')
        except Exception:
            pass
    conn.set_trace_callback(trace)
    return conn

sqlite3.connect = _audited_connect

try:
    import networkx as nx
    _real_pagerank = nx.pagerank

    def _audited_pagerank(*args, **kwargs):
        alpha = kwargs.get('alpha', args[1] if len(args) > 1 else 0.85)
        weight = kwargs.get('weight', args[6] if len(args) > 6 else 'weight')
        try:
            with open('/tmp/etl_networkx.log', 'a') as f:
                f.write(json.dumps({'alpha': alpha, 'weight': weight}) + '\\n')
        except Exception:
            pass
        return _real_pagerank(*args, **kwargs)

    nx.pagerank = _audited_pagerank
    try:
        import networkx.algorithms.link_analysis.pagerank_alg as _pagerank_alg
        _pagerank_alg.pagerank = _audited_pagerank
    except Exception:
        pass
except Exception:
    pass
'''


def install_audit_hook():
    os.makedirs(AUDIT_DIR, exist_ok=True)
    with open(os.path.join(AUDIT_DIR, 'sitecustomize.py'), 'w') as f:
        f.write(SITE_CUSTOMIZE)


def assert_required_operations_were_executed():
    assert os.path.isfile(SQL_LOG), 'The script did not execute an SQLite query'
    with open(SQL_LOG, 'r') as f:
        statements = f.read().upper().split('--STATEMENT--')

    qualifying = [s for s in statements if 'WITH' in s and 'RANK' in s and 'OVER' in s]
    assert qualifying, 'No executed SQL statement used a CTE and RANK() window function'
    assert any(s.count('JOIN') >= 2 for s in qualifying), \
        'The CTE/window query must perform the required joins'

    assert os.path.isfile(NX_LOG), 'The script did not call NetworkX pagerank'
    calls = []
    with open(NX_LOG, 'r') as f:
        for line in f:
            if line.strip():
                calls.append(json.loads(line))
    assert any(abs(float(c.get('alpha')) - 0.85) < 1e-12 and c.get('weight') == 'weight' for c in calls), \
        "NetworkX pagerank was not called with alpha=0.85 and weight='weight'"


def run_pipeline_audited():
    for path in (SQL_LOG, NX_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH', '')
    env['PYTHONPATH'] = AUDIT_DIR + (os.pathsep + old_pythonpath if old_pythonpath else '')
    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, \
        f'etl_pipeline.py failed with exit code {completed.returncode}:\n{completed.stderr}'
    assert_required_operations_were_executed()


def compute_pagerank(nodes, edges, alpha=0.85, max_iter=100, tol=1.0e-6):
    """Computes PageRank as NetworkX does for weighted directed graphs."""
    N = len(nodes)
    if N == 0:
        return {}

    out_weight = {u: sum(edges.get(u, {}).values()) for u in nodes}
    x = {u: 1.0 / N for u in nodes}

    for _ in range(max_iter):
        xlast = x.copy()
        x = {u: 0.0 for u in nodes}
        danglesum = alpha * sum(xlast[u] for u in nodes if out_weight[u] == 0)

        for u in nodes:
            for v, w in edges.get(u, {}).items():
                x[v] += alpha * xlast[u] * w / out_weight[u]
            x[u] += danglesum / N + (1.0 - alpha) / N

        err = sum(abs(x[u] - xlast[u]) for u in nodes)
        if err < tol:
            break

    return x


def get_truth_data():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute('''
        SELECT u.id, u.name, d.name
        FROM users u
        JOIN departments d ON u.department_id = d.id
    ''')
    users = {row[0]: {'name': row[1], 'department_name': row[2]} for row in cursor.fetchall()}

    cursor.execute('SELECT sender_id, receiver_id FROM messages')
    messages = cursor.fetchall()
    conn.close()

    sent_counts = {u: 0 for u in users}
    for sender, _ in messages:
        if sender in sent_counts:
            sent_counts[sender] += 1

    dept_users = {}
    for uid, uinfo in users.items():
        dept = uinfo['department_name']
        dept_users.setdefault(dept, []).append((uid, sent_counts[uid]))

    dept_ranks = {}
    for dept, ulist in dept_users.items():
        ulist.sort(key=lambda x: x[1], reverse=True)
        rank = 1
        for i, (uid, count) in enumerate(ulist):
            if i > 0 and count < ulist[i - 1][1]:
                rank = i + 1
            dept_ranks[uid] = rank

    nodes = list(users.keys())
    edges = {}
    for sender, receiver in messages:
        edges.setdefault(sender, {})
        edges[sender][receiver] = edges[sender].get(receiver, 0) + 1

    pageranks = compute_pagerank(nodes, edges)

    results = []
    for uid in users:
        results.append({
            'user_id': uid,
            'name': users[uid]['name'],
            'department_name': users[uid]['department_name'],
            'messages_sent': sent_counts[uid],
            'dept_rank': dept_ranks[uid],
            'pagerank': round(pageranks[uid], 4),
        })

    results.sort(key=lambda x: x['pagerank'], reverse=True)
    return results[:3]


def load_and_check_output(expected):
    assert os.path.exists(OUTPUT_PATH), f'Output file not found at {OUTPUT_PATH}'
    assert os.path.isfile(OUTPUT_PATH), f'Path {OUTPUT_PATH} is not a file'

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('Output file is not valid JSON')

    assert isinstance(data, list), 'JSON output must be a list of dictionaries'
    assert len(data) == 3, f'Expected exactly 3 users in output, got {len(data)}'

    for i, (actual, wanted) in enumerate(zip(data, expected)):
        assert isinstance(actual, dict), f'Item at index {i} is not a dictionary'
        expected_keys = {'user_id', 'name', 'department_name', 'messages_sent', 'dept_rank', 'pagerank'}
        assert set(actual.keys()) == expected_keys, \
            f'Item at index {i} has incorrect keys. Expected {expected_keys}, got {set(actual.keys())}'
        assert actual['user_id'] == wanted['user_id'], \
            f"Rank {i+1}: Expected user_id {wanted['user_id']}, got {actual['user_id']}"
        assert actual['name'] == wanted['name'], \
            f"Rank {i+1}: Expected name {wanted['name']}, got {actual['name']}"
        assert actual['department_name'] == wanted['department_name'], \
            f"Rank {i+1}: Expected dept {wanted['department_name']}, got {actual['department_name']}"
        assert actual['messages_sent'] == wanted['messages_sent'], \
            f"Rank {i+1}: Expected messages_sent {wanted['messages_sent']}, got {actual['messages_sent']}"
        assert actual['dept_rank'] == wanted['dept_rank'], \
            f"Rank {i+1}: Expected dept_rank {wanted['dept_rank']}, got {actual['dept_rank']}"
        assert isinstance(actual['pagerank'], (int, float)) and not isinstance(actual['pagerank'], bool)
        assert abs(actual['pagerank'] - wanted['pagerank']) <= 0.0002, \
            f"Rank {i+1}: Expected pagerank ~{wanted['pagerank']}, got {actual['pagerank']}"


@pytest.fixture(scope='session', autouse=True)
def execute_submitted_pipeline():
    install_audit_hook()
    assert os.path.exists(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    assert os.path.isfile(SCRIPT_PATH), f'Path {SCRIPT_PATH} is not a regular file'
    try:
        os.remove(OUTPUT_PATH)
    except FileNotFoundError:
        pass
    run_pipeline_audited()


def test_script_exists_and_is_file():
    assert os.path.exists(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    assert os.path.isfile(SCRIPT_PATH), f'Path {SCRIPT_PATH} is not a regular file'


def test_output_file_exists():
    assert os.path.exists(OUTPUT_PATH), f'Output file not found at {OUTPUT_PATH}'
    assert os.path.isfile(OUTPUT_PATH), f'Path {OUTPUT_PATH} is not a file'


def test_output_json_format_and_values():
    load_and_check_output(get_truth_data())


def populate_random_database():
    rng = random.SystemRandom()
    token = uuid.uuid4().hex[:10]
    base = rng.randrange(1000, 50000) * 10
    user_ids = [base + i for i in range(1, 9)]
    dept_ids = [base + 101, base + 102, base + 103, base + 104]

    while True:
        edge_weights = {}
        for sender in user_ids:
            for receiver in user_ids:
                if sender != receiver and rng.random() < 0.42:
                    edge_weights[(sender, receiver)] = rng.randint(1, 7)

        for i, sender in enumerate(user_ids):
            if not any(s == sender for s, _ in edge_weights):
                edge_weights[(sender, user_ids[(i + 1) % len(user_ids)])] = rng.randint(1, 7)
        for i, receiver in enumerate(user_ids):
            if not any(r == receiver for _, r in edge_weights):
                edge_weights[(user_ids[(i - 1) % len(user_ids)], receiver)] = rng.randint(1, 7)

        graph_edges = {}
        for (sender, receiver), weight in edge_weights.items():
            graph_edges.setdefault(sender, {})[receiver] = weight
        ranks = compute_pagerank(user_ids, graph_edges)
        rounded = sorted((round(v, 4) for v in ranks.values()), reverse=True)
        if len(set(rounded[:4])) == 4:
            break

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute('DELETE FROM messages')
    cur.execute('DELETE FROM users')
    cur.execute('DELETE FROM departments')

    for i, dept_id in enumerate(dept_ids):
        cur.execute('INSERT INTO departments (id, name) VALUES (?, ?)',
                    (dept_id, f'DynamicDept_{token}_{i}'))
    for i, uid in enumerate(user_ids):
        cur.execute('INSERT INTO users (id, name, department_id) VALUES (?, ?, ?)',
                    (uid, f'DynamicUser_{token}_{i}', dept_ids[i // 2]))

    message_id = 1
    for (sender, receiver), weight in edge_weights.items():
        for _ in range(weight):
            cur.execute(
                'INSERT INTO messages (id, sender_id, receiver_id, timestamp) VALUES (?, ?, ?, ?)',
                (message_id, sender, receiver, '2026-01-02 03:04:05'),
            )
            message_id += 1
    conn.commit()
    conn.close()


def test_pipeline_generalizes_to_unseen_database():
    fd, backup_path = tempfile.mkstemp(prefix='comms_backup_', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    old_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, 'rb') as f:
            old_output = f.read()

    try:
        populate_random_database()
        try:
            os.remove(OUTPUT_PATH)
        except FileNotFoundError:
            pass
        run_pipeline_audited()
        load_and_check_output(get_truth_data())
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
        if old_output is not None:
            os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
            with open(OUTPUT_PATH, 'wb') as f:
                f.write(old_output)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
