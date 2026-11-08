#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import secrets
import sqlite3
import subprocess
import tempfile


def test_video_frame_extraction():
    output_csv = "/home/user/keyframes.csv"
    assert os.path.isfile(output_csv), f"Missing keyframes CSV file at {output_csv}"

    video_path = "/app/foraging_behavior.mp4"
    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "frame=pkt_pts_time,pict_type",
        "-of", "csv=print_section=0", video_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)

    expected_timestamps = []
    for line in result.stdout.strip().split('\n'):
        if not line:
            continue
        parts = line.split(',')
        if len(parts) >= 2 and parts[1] == 'I':
            expected_timestamps.append(float(parts[0]))
    expected_timestamps.sort()

    student_timestamps = []
    with open(output_csv, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['timestamp'], "CSV header must be exactly 'timestamp'"
        for row in reader:
            if row:
                student_timestamps.append(float(row[0]))

    assert student_timestamps == expected_timestamps, \
        "Extracted keyframe timestamps do not match the expected I-frame timestamps"


def graph_has_cycle(records):
    parents = {record['id']: record['parent_id'] for record in records}
    done = set()
    for start in parents:
        if start in done:
            continue
        current = start
        active = set()
        while current is not None and current in parents and current not in done:
            if current in active:
                return True
            active.add(current)
            current = parents[current]
        done.update(active)
    return False


def run_detector(script_path, path):
    result = subprocess.run(
        ["python3", script_path, path], capture_output=True, timeout=5
    )
    return result.returncode


def test_adversarial_metadata_filtering():
    script_path = "/home/user/cycle_detector.py"
    assert os.path.isfile(script_path), f"Missing script at {script_path}"

    clean_dir = "/app/taxonomy_corpus/clean"
    evil_dir = "/app/taxonomy_corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]

    failed_clean = [os.path.basename(p) for p in clean_files if run_detector(script_path, p) != 0]
    failed_evil = [os.path.basename(p) for p in evil_files if run_detector(script_path, p) == 0]

    error_msg = []
    if failed_evil:
        error_msg.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        error_msg.append(f"{len(failed_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(failed_clean)}")
    assert not error_msg, "; ".join(error_msg)

    rng = random.SystemRandom()
    generated = []

    # Unpredictable valid forests with non-consecutive IDs and shuffled records.
    for size in (1, 4, 9, 17):
        ids = rng.sample(range(1000, 1000000), size)
        records = []
        for i, node_id in enumerate(ids):
            parent = None if i == 0 or rng.random() < 0.3 else rng.choice(ids[:i])
            records.append({'id': node_id, 'parent_id': parent})
        rng.shuffle(records)
        generated.append(records)

    # Unpredictable graphs containing cycles, including cycles hidden in forests.
    for size, cycle_len in ((2, 2), (7, 3), (13, 5)):
        ids = rng.sample(range(1000, 1000000), size)
        records = []
        for i in range(cycle_len):
            records.append({'id': ids[i], 'parent_id': ids[(i + 1) % cycle_len]})
        for i in range(cycle_len, size):
            parent = None if rng.random() < 0.25 else rng.choice(ids[:i])
            records.append({'id': ids[i], 'parent_id': parent})
        rng.shuffle(records)
        generated.append(records)

    self_id = rng.randrange(1000001, 2000000)
    generated.append([{'id': self_id, 'parent_id': self_id}])
    rng.shuffle(generated)

    with tempfile.TemporaryDirectory(prefix="metadata_checks_") as temp_dir:
        for records in generated:
            path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
            with open(path, 'w') as f:
                json.dump(records, f)
            expected = 1 if graph_has_cycle(records) else 0
            actual = run_detector(script_path, path)
            assert actual == expected, \
                f"Cycle detector returned {actual} instead of {expected} for generated metadata"


def load_schema(connection, schema_path):
    with open(schema_path, 'r') as f:
        connection.executescript(f.read())


def table_columns(cursor, table):
    cursor.execute(f"PRAGMA table_info({table})")
    return {row[1]: row for row in cursor.fetchall()}


def test_database_schema_and_index():
    schema_path = "/home/user/schema.sql"
    assert os.path.isfile(schema_path), f"Missing schema script at {schema_path}"

    with tempfile.NamedTemporaryFile(suffix=".db") as tmpdb:
        conn = sqlite3.connect(tmpdb.name)
        cursor = conn.cursor()
        load_schema(conn, schema_path)

        cursor.execute("SELECT type FROM sqlite_master WHERE name='taxonomy'")
        assert cursor.fetchone() == ('table',), "taxonomy must be a table"
        cursor.execute("SELECT type FROM sqlite_master WHERE name='keyframes'")
        assert cursor.fetchone() == ('table',), "keyframes must be a table"

        tax_cols = table_columns(cursor, 'taxonomy')
        assert {'id', 'parent_id', 'name'}.issubset(tax_cols), \
            "taxonomy table missing required columns"
        assert tax_cols['id'][2].upper() == 'INTEGER', "taxonomy.id must be declared INTEGER"
        assert tax_cols['id'][5] > 0, "taxonomy.id must be the primary key"
        assert tax_cols['parent_id'][2].upper() == 'INTEGER', \
            "taxonomy.parent_id must be declared INTEGER"
        assert tax_cols['name'][2].upper() == 'TEXT', "taxonomy.name must be declared TEXT"

        cursor.execute("PRAGMA foreign_key_list(taxonomy)")
        foreign_keys = cursor.fetchall()
        assert any(row[2] == 'taxonomy' and row[3] == 'parent_id' and row[4] == 'id'
                   for row in foreign_keys), \
            "taxonomy.parent_id must reference taxonomy.id"

        kf_cols = table_columns(cursor, 'keyframes')
        assert {'id', 'video_name', 'timestamp'}.issubset(kf_cols), \
            "keyframes table missing required columns"
        assert kf_cols['id'][2].upper() == 'INTEGER', "keyframes.id must be declared INTEGER"
        assert kf_cols['id'][5] > 0, "keyframes.id must be the primary key"
        assert kf_cols['video_name'][2].upper() == 'TEXT', \
            "keyframes.video_name must be declared TEXT"
        assert kf_cols['timestamp'][2].upper() == 'REAL', \
            "keyframes.timestamp must be declared REAL"

        cursor.execute("SELECT sql, tbl_name FROM sqlite_master WHERE type='index' AND name='idx_keyframes_video_time'")
        idx_row = cursor.fetchone()
        assert idx_row is not None, "Index idx_keyframes_video_time does not exist"
        idx_sql = idx_row[0].lower()
        assert "video_name" in idx_sql and "timestamp" in idx_sql, \
            "Index does not cover video_name and timestamp"
        assert idx_row[1] == 'keyframes', "Index idx_keyframes_video_time must index keyframes"

        cursor.execute("PRAGMA index_info(idx_keyframes_video_time)")
        indexed_columns = [row[2] for row in cursor.fetchall()]
        assert indexed_columns[:2] == ['video_name', 'timestamp'], \
            "Index must begin with video_name followed by timestamp"
        conn.close()


def strip_sql_comments_and_literals(sql):
    pattern = re.compile(
        r"--[^\n]*(?:\n|$)|/\*.*?\*/|'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"|`[^`]*`|\[[^\]]*\]",
        re.DOTALL
    )
    return pattern.sub(' ', sql)


def make_taxonomy_dataset(rng, depth):
    count = depth + 5
    ids = rng.sample(range(10000, 9000000), count)
    token = secrets.token_hex(5)
    rows = []

    # A deep chain forces genuinely recursive path construction.
    for i in range(depth):
        parent = None if i == 0 else ids[i - 1]
        rows.append((ids[i], parent, f"node_{token}_{i}"))

    # Add another root and branches, with IDs unrelated to hierarchy order.
    rows.append((ids[depth], None, f"root_{token}"))
    rows.append((ids[depth + 1], ids[depth], f"branch_{token}_1"))
    rows.append((ids[depth + 2], ids[2], f"branch_{token}_2"))
    rows.append((ids[depth + 3], ids[depth + 2], f"leaf_{token}"))
    rows.append((ids[depth + 4], None, f"solo_{token}"))
    rng.shuffle(rows)
    return rows


def expected_paths(rows):
    by_id = {node_id: (parent_id, name) for node_id, parent_id, name in rows}
    expected = []
    for node_id, (parent_id, name) in by_id.items():
        names = [name]
        current = parent_id
        while current is not None:
            current_parent, current_name = by_id[current]
            names.append(current_name)
            current = current_parent
        expected.append((node_id, name, ' > '.join(reversed(names))))
    return sorted(expected, key=lambda row: row[0])


def test_recursive_query_construction():
    schema_path = "/home/user/schema.sql"
    query_path = "/home/user/recursive_export.sql"
    assert os.path.isfile(query_path), f"Missing recursive query script at {query_path}"

    with open(query_path, 'r') as f:
        query = f.read()
    structural_sql = strip_sql_comments_and_literals(query)
    assert re.search(r"\bWITH\s+RECURSIVE\b", structural_sql, re.IGNORECASE), \
        "recursive_export.sql must use a WITH RECURSIVE CTE"

    # Retain the original fixture assertion.
    datasets = [[
        (1, None, 'Animalia'),
        (2, 1, 'Chordata'),
        (3, 2, 'Mammalia'),
        (4, 3, 'Carnivora'),
        (5, None, 'Plantae')
    ]]

    rng = random.SystemRandom()
    datasets.extend(make_taxonomy_dataset(rng, depth) for depth in (7, 10, 13))

    for test_data in datasets:
        with tempfile.NamedTemporaryFile(suffix=".db") as tmpdb:
            conn = sqlite3.connect(tmpdb.name)
            cursor = conn.cursor()
            load_schema(conn, schema_path)
            cursor.executemany(
                "INSERT INTO taxonomy (id, parent_id, name) VALUES (?, ?, ?)", test_data
            )
            conn.commit()

            cursor.execute(query)
            results = cursor.fetchall()
            column_names = [description[0].lower() for description in cursor.description]
            assert column_names == ['id', 'name', 'path'], \
                "Recursive query must output exactly id, name, and path"

            expected = expected_paths(test_data)
            assert sorted(results, key=lambda row: row[0]) == expected, \
                "Recursive query output does not match expected hierarchical paths"
            assert [row[0] for row in results] == [row[0] for row in expected], \
                "Results are not sorted by id ascending"
            conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
