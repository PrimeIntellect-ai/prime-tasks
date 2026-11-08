#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
import pytest

DB_PATH = '/home/user/citation_graph.db'
JSON_PATH = '/home/user/top_nodes.json'
BINARY_PATH = '/home/user/graph_analyzer'


def read_json():
    assert os.path.isfile(JSON_PATH), f"Output JSON file {JSON_PATH} is missing."
    try:
        with open(JSON_PATH, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON in {JSON_PATH}: {e}")


def expected_from_database(db_path):
    conn = sqlite3.connect(db_path)
    try:
        node_ids = [row[0] for row in conn.execute('SELECT paper_id FROM papers')]
        degrees = {node_id: 0 for node_id in node_ids}
        for source_id, target_id in conn.execute('SELECT source_id, target_id FROM citations'):
            if source_id in degrees:
                degrees[source_id] += 1
            if target_id in degrees:
                degrees[target_id] += 1
        ranked = sorted(degrees.items(), key=lambda item: (-item[1], item[0]))[:3]
        return {
            'top_nodes': [
                {'node_id': node_id, 'degree': degree}
                for node_id, degree in ranked
            ]
        }
    finally:
        conn.close()


def test_db_duplicates_removed():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT source_id, target_id, COUNT(*)
        FROM citations
        GROUP BY source_id, target_id
        HAVING COUNT(*) > 1
    """)
    duplicates = cursor.fetchall()
    conn.close()

    assert len(duplicates) == 0, f"Found {len(duplicates)} duplicate pairs in the citations table. Duplicates were not removed."


def test_db_unique_index_created():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA index_list('citations')")
    indexes = cursor.fetchall()

    unique_index_found = False
    for idx in indexes:
        idx_name = idx[1]
        is_unique = idx[2]
        if is_unique:
            cursor.execute(f"PRAGMA index_info('{idx_name}')")
            cols = cursor.fetchall()
            col_names = {col[2] for col in cols}
            if col_names == {'source_id', 'target_id'}:
                unique_index_found = True
                break

    conn.close()
    assert unique_index_found, "A UNIQUE index on (source_id, target_id) was not found in the citations table."


def test_c_source_file_exists():
    c_path = '/home/user/graph_analyzer.c'
    assert os.path.isfile(c_path), f"C source file {c_path} is missing."


def test_json_output_correct():
    data = read_json()
    expected = {
        "top_nodes": [
            {"node_id": 3, "degree": 9},
            {"node_id": 1, "degree": 7},
            {"node_id": 2, "degree": 6}
        ]
    }
    assert data == expected, f"JSON content mismatch. Expected {expected}, but got {data}."


def test_analyzer_calculates_total_degree_from_database():
    fd, backup_path = tempfile.mkstemp(prefix='citation_graph_backup_', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)

    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute('DELETE FROM citations')
            conn.executemany(
                'INSERT INTO citations (source_id, target_id) VALUES (?, ?)',
                [(10, 9), (10, 8), (10, 7), (9, 8), (6, 10)]
            )
            conn.commit()
        finally:
            conn.close()

        expected = expected_from_database(DB_PATH)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        subprocess.run([BINARY_PATH], check=True, timeout=10)
        actual = read_json()
        assert actual == expected, f"Analyzer did not calculate total degree from the database. Expected {expected}, but got {actual}."
    finally:
        for suffix in ('-wal', '-shm'):
            sidecar = DB_PATH + suffix
            if os.path.exists(sidecar):
                os.remove(sidecar)
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        subprocess.run([BINARY_PATH], check=False, timeout=10)
TEST_EOF

if gcc -std=c11 /home/user/graph_analyzer.c -o /home/user/graph_analyzer -lsqlite3 \
   && rm -f /home/user/top_nodes.json \
   && timeout 10 /home/user/graph_analyzer \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
