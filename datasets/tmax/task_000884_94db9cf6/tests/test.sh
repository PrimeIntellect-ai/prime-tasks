#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import sqlite3


def compute_expected_backup_size():
    db_path = '/home/user/backups.db'
    assert os.path.exists(db_path), f"Database file {db_path} does not exist."

    with sqlite3.connect(db_path) as conn:
        row = conn.execute(
            """
            SELECT SUM(b.size_bytes)
            FROM servers AS s
            JOIN backups AS b ON b.server_id = s.id
            WHERE s.hostname = ? AND b.status = ?
            """,
            ('db-prod-01', 'SUCCESS'),
        ).fetchone()

    assert row is not None and row[0] is not None, "The corrected backup query returned no total."
    return row[0]


def compute_expected_restore_time():
    graph_path = '/home/user/dependency_graph.json'
    assert os.path.exists(graph_path), f"Graph file {graph_path} does not exist."
    assert os.path.isfile(graph_path), f"{graph_path} is not a file."

    with open(graph_path, 'r') as f:
        documents = json.load(f)

    nodes = {doc['backup_id']: doc for doc in documents}
    assert 1 in nodes and 50 in nodes, "Dependency graph must contain backup IDs 1 and 50."

    outgoing = {backup_id: [] for backup_id in nodes}
    for doc in documents:
        for dependency in doc['depends_on']:
            if dependency in nodes:
                outgoing[dependency].append(doc['backup_id'])

    distances = {1: nodes[1]['restore_time_minutes']}
    queue = [(distances[1], 1)]

    while queue:
        total, backup_id = heapq.heappop(queue)
        if total != distances.get(backup_id):
            continue
        if backup_id == 50:
            return total

        for successor in outgoing[backup_id]:
            candidate = total + nodes[successor]['restore_time_minutes']
            if candidate < distances.get(successor, float('inf')):
                distances[successor] = candidate
                heapq.heappush(queue, (candidate, successor))

    raise AssertionError("No valid restoration path exists from backup ID 1 to backup ID 50.")


def test_report_content():
    report_path = '/home/user/report.txt'
    assert os.path.exists(report_path), f"Report file {report_path} does not exist."
    assert os.path.isfile(report_path), f"{report_path} is not a file."

    with open(report_path, 'r') as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        f"Total Backup Size: {compute_expected_backup_size()}",
        f"Shortest Restore Time: {compute_expected_restore_time()}",
    ]

    assert len(content) >= 2, f"Report file {report_path} does not contain enough lines."
    assert content[0].strip() == expected_lines[0], (
        f"First line of report is incorrect. Expected '{expected_lines[0]}', "
        f"got '{content[0].strip()}'"
    )
    assert content[1].strip() == expected_lines[1], (
        f"Second line of report is incorrect. Expected '{expected_lines[1]}', "
        f"got '{content[1].strip()}'"
    )


def test_backups_table_index():
    db_path = '/home/user/backups.db'
    assert os.path.exists(db_path), f"Database file {db_path} does not exist."

    with sqlite3.connect(db_path) as conn:
        indexes = conn.execute(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'index'
              AND tbl_name = 'backups'
              AND name NOT LIKE 'sqlite_autoindex%'
            """
        ).fetchall()

        assert len(indexes) > 0, (
            "No custom index found on the 'backups' table. You must create an "
            "appropriate index to optimize the query."
        )

        suitable = []
        for (index_name,) in indexes:
            escaped_name = index_name.replace("'", "''")
            columns = conn.execute(
                f"PRAGMA index_info('{escaped_name}')"
            ).fetchall()
            leading_columns = [row[2].lower() for row in columns[:2] if row[2] is not None]
            if len(leading_columns) == 2 and set(leading_columns) == {'server_id', 'status'}:
                suitable.append(index_name)

    assert suitable, (
        "No custom index on 'backups' has server_id and status as its two leading "
        "columns; such an index is required to optimize the join and status filter."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
