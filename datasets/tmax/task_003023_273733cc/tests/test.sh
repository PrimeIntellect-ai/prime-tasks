#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import tempfile
import uuid

SCRIPT_PATH = '/home/user/analyze_graph.sh'
DB_PATH = '/home/user/infra_graph.db'
LOG_PATH = '/home/user/output.log'


def run_script(db_path):
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    result = subprocess.run([SCRIPT_PATH, db_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed for {db_path}. STDERR:\n{result.stderr}"
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} was not created."
    with open(LOG_PATH, 'r') as f:
        return f.read().strip()


def assert_projection_and_index(db_path, expected_data):
    conn = sqlite3.connect(db_path)
    try:
        c = conn.cursor()
        c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='ServiceDependencyGraph';")
        assert c.fetchone() is not None, "Table 'ServiceDependencyGraph' was not created."

        c.execute("SELECT source, target FROM ServiceDependencyGraph ORDER BY source, target;")
        data = c.fetchall()
        assert data == expected_data, "Data in 'ServiceDependencyGraph' does not match the expected projection."

        c.execute("PRAGMA index_list('ServiceDependencyGraph');")
        indexes = c.fetchall()
        assert len(indexes) > 0, "No indexes found on 'ServiceDependencyGraph'."

        has_source_index = False
        for idx in indexes:
            idx_name = idx[1].replace("'", "''")
            c.execute(f"PRAGMA index_info('{idx_name}');")
            columns = c.fetchall()
            if columns and columns[0][2] == 'source':
                has_source_index = True
                break
        assert has_source_index, "No index found on the 'source' column of 'ServiceDependencyGraph' to optimize forward traversal."
    finally:
        conn.close()


def derive_answers(db_path):
    conn = sqlite3.connect(db_path)
    try:
        c = conn.cursor()
        c.execute("""
            SELECT e.source, e.target
            FROM Edges e
            JOIN Nodes s ON s.id = e.source
            JOIN Nodes t ON t.id = e.target
            WHERE e.type = 'DEPENDS_ON'
              AND s.label = 'Service'
              AND t.label = 'Service'
            ORDER BY e.source, e.target
        """)
        projection = c.fetchall()

        c.execute("""
            SELECT DISTINCT service.name
            FROM Nodes service
            JOIN Edges dependency
              ON dependency.source = service.id
             AND dependency.type = 'DEPENDS_ON'
            JOIN Nodes database_node
              ON database_node.id = dependency.target
             AND database_node.label = 'Database'
            JOIN Edges hosting
              ON hosting.source = database_node.id
             AND hosting.type = 'HOSTED_ON'
            JOIN Nodes server
              ON server.id = hosting.target
             AND server.label = 'Server'
            WHERE service.label = 'Service'
              AND server.name = 'srv-core-01'
            ORDER BY service.name
        """)
        names = [row[0] for row in c.fetchall()]
    finally:
        conn.close()

    adjacency = {}
    for source, target in projection:
        adjacency.setdefault(source, []).append(target)
    frontier = [('GatewayAPI', 0)]
    seen = {'GatewayAPI'}
    shortest = None
    while frontier:
        node, distance = frontier.pop(0)
        if node == 'PaymentProcessor':
            shortest = distance
            break
        for target in adjacency.get(node, []):
            if target not in seen:
                seen.add(target)
                frontier.append((target, distance + 1))
    assert shortest is not None, "Generated test database must contain a path."

    expected_log = "--- Pattern Match ---\n"
    if names:
        expected_log += "\n".join(names) + "\n"
    expected_log += f"--- Shortest Path ---\n{shortest}"
    return projection, expected_log


def create_dynamic_db(path, variant):
    token = uuid.uuid4().hex[:10]
    conn = sqlite3.connect(path)
    try:
        c = conn.cursor()
        c.execute('CREATE TABLE Nodes (id TEXT PRIMARY KEY, label TEXT, name TEXT)')
        c.execute('CREATE TABLE Edges (source TEXT, target TEXT, type TEXT)')

        if variant == 0:
            alpha = f'Alpha-{token}'
            zulu = f'Zulu-{token}'
            db1 = f'db-one-{token}'
            db2 = f'db-two-{token}'
            other = f'srv-other-{token}'
            nodes = [
                ('GatewayAPI', 'Service', 'GatewayAPI'),
                ('PaymentProcessor', 'Service', 'PaymentProcessor'),
                (alpha, 'Service', alpha),
                (zulu, 'Service', zulu),
                (db1, 'Database', db1),
                (db2, 'Database', db2),
                ('srv-core-01', 'Server', 'srv-core-01'),
                (other, 'Server', other),
            ]
            edges = [
                ('GatewayAPI', 'PaymentProcessor', 'DEPENDS_ON'),
                ('GatewayAPI', alpha, 'DEPENDS_ON'),
                (alpha, zulu, 'DEPENDS_ON'),
                (alpha, db1, 'DEPENDS_ON'),
                (zulu, db2, 'DEPENDS_ON'),
                (db1, 'srv-core-01', 'HOSTED_ON'),
                (db2, 'srv-core-01', 'HOSTED_ON'),
                ('PaymentProcessor', other, 'HOSTED_ON'),
            ]
        else:
            h1 = f'Hop-A-{token}'
            h2 = f'Hop-B-{token}'
            h3 = f'Hop-C-{token}'
            extra = f'Extra-{token}'
            db1 = f'db-main-{token}'
            db2 = f'db-extra-{token}'
            nodes = [
                ('GatewayAPI', 'Service', 'GatewayAPI'),
                ('PaymentProcessor', 'Service', 'PaymentProcessor'),
                (h1, 'Service', h1),
                (h2, 'Service', h2),
                (h3, 'Service', h3),
                (extra, 'Service', extra),
                (db1, 'Database', db1),
                (db2, 'Database', db2),
                ('srv-core-01', 'Server', 'srv-core-01'),
            ]
            edges = [
                ('GatewayAPI', h1, 'DEPENDS_ON'),
                (h1, h2, 'DEPENDS_ON'),
                (h2, h3, 'DEPENDS_ON'),
                (h3, 'PaymentProcessor', 'DEPENDS_ON'),
                ('GatewayAPI', extra, 'DEPENDS_ON'),
                (h1, db1, 'DEPENDS_ON'),
                (extra, db2, 'DEPENDS_ON'),
                (db1, 'srv-core-01', 'HOSTED_ON'),
                (db2, 'srv-core-01', 'HOSTED_ON'),
            ]

        c.executemany('INSERT INTO Nodes VALUES (?,?,?)', nodes)
        c.executemany('INSERT INTO Edges VALUES (?,?,?)', edges)
        conn.commit()
    finally:
        conn.close()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_original_database_execution_output_and_changes():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."
    log_content = run_script(DB_PATH)
    expected_log = (
        "--- Pattern Match ---\n"
        "AuthService\n"
        "BillingService\n"
        "--- Shortest Path ---\n"
        "2"
    )
    assert log_content == expected_log, f"Content of {LOG_PATH} does not match expected output.\nExpected:\n{expected_log}\nGot:\n{log_content}"

    expected_data = [
        ('BillingService', 'PaymentProcessor'),
        ('GatewayAPI', 'AuthService'),
        ('GatewayAPI', 'BillingService'),
        ('GatewayAPI', 'InventoryService')
    ]
    assert_projection_and_index(DB_PATH, expected_data)


def test_script_uses_supplied_database_dynamically():
    for variant in (0, 1):
        fd, db_path = tempfile.mkstemp(prefix='infra_graph_dynamic_', suffix='.db')
        os.close(fd)
        try:
            create_dynamic_db(db_path, variant)
            expected_projection, expected_log = derive_answers(db_path)
            actual_log = run_script(db_path)
            assert actual_log == expected_log, f"Dynamic output mismatch.\nExpected:\n{expected_log}\nGot:\n{actual_log}"
            assert_projection_and_index(db_path, expected_projection)
        finally:
            if os.path.exists(db_path):
                os.remove(db_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
