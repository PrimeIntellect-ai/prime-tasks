#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import cv2
import pandas as pd
import numpy as np

DB_PATH = "/home/user/sensor_graph.db"
CSV_PATH = "/home/user/edges_export.csv"
VIDEO_PATH = "/app/grid_flash.mp4"


def extract_expected_edges():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open video at {VIDEO_PATH}"

    adjacency = []
    for r in range(5):
        for c in range(5):
            node = r * 5 + c
            if c < 4:
                adjacency.append((node, node + 1))
            if r < 4:
                adjacency.append((node, node + 5))

    weights = {edge: 0 for edge in adjacency}
    frame_count = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_count += 1
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        active = set()
        for r in range(5):
            for c in range(5):
                center = gray[r * 100 + 45:r * 100 + 55,
                              c * 100 + 45:c * 100 + 55]
                if float(center.mean()) > 128:
                    active.add(r * 5 + c)
        for u, v in adjacency:
            if u in active and v in active:
                weights[(u, v)] += 1

    cap.release()
    assert frame_count == 300, f"Expected 300 video frames, decoded {frame_count}"
    return pd.DataFrame(
        [(u, v, weight) for (u, v), weight in weights.items() if weight > 0],
        columns=['source', 'target', 'weight']
    )


def test_db_exists_and_schema():
    assert os.path.exists(DB_PATH), f"Database not found at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='edges'")
    assert cursor.fetchone() is not None, "Table 'edges' does not exist in the database."

    cursor.execute("PRAGMA table_info(edges)")
    columns = {row[1] for row in cursor.fetchall()}
    assert {'source', 'target', 'weight'}.issubset(columns), f"Table 'edges' is missing required columns. Found: {columns}"

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges'")
    indices = [row[0] for row in cursor.fetchall()]

    index_on_weight = False
    for idx in indices:
        if idx and idx.startswith('sqlite_autoindex'):
            continue
        escaped = idx.replace('"', '""')
        cursor.execute(f'PRAGMA index_info("{escaped}")')
        idx_cols = [row[2] for row in cursor.fetchall()]
        if 'weight' in idx_cols:
            index_on_weight = True
            break

    assert index_on_weight, "No index found on the 'weight' column in the 'edges' table."
    conn.close()


def test_csv_exists_and_format():
    assert os.path.exists(CSV_PATH), f"CSV export not found at {CSV_PATH}"

    df = pd.read_csv(CSV_PATH)
    assert list(df.columns) == ['source', 'target', 'weight'], f"CSV columns are incorrect. Expected ['source', 'target', 'weight'], found: {list(df.columns)}"

    weights = df['weight'].tolist()
    assert weights == sorted(weights, reverse=True), "CSV is not sorted by weight descending."
    assert (df['source'] < df['target']).all(), "There are rows where source is not less than target."
    assert (df['weight'] > 0).all(), "There are rows with weight <= 0."

    valid_edges = {
        (node, node + 1)
        for node in range(25) if node % 5 < 4
    } | {
        (node, node + 5)
        for node in range(20)
    }
    actual_edges = list(zip(df['source'], df['target']))
    assert len(actual_edges) == len(set(actual_edges)), "CSV contains duplicate edges."
    assert all(edge in valid_edges for edge in actual_edges), "CSV contains non-adjacent edges."


def test_database_contents_match_csv():
    csv_df = pd.read_csv(CSV_PATH)[['source', 'target', 'weight']]
    conn = sqlite3.connect(DB_PATH)
    db_df = pd.read_sql_query("SELECT source, target, weight FROM edges", conn)
    conn.close()

    csv_sorted = csv_df.sort_values(['source', 'target', 'weight']).reset_index(drop=True)
    db_sorted = db_df.sort_values(['source', 'target', 'weight']).reset_index(drop=True)
    pd.testing.assert_frame_equal(db_sorted, csv_sorted, check_dtype=False)


def test_mae_metric():
    assert os.path.exists(CSV_PATH), f"CSV export not found at {CSV_PATH}"

    ref = extract_expected_edges().set_index(['source', 'target'])
    pred = pd.read_csv(CSV_PATH).set_index(['source', 'target'])

    merged = ref.join(pred, lsuffix='_ref', rsuffix='_pred', how='outer').fillna(0)
    mae = np.mean(np.abs(merged['weight_ref'] - merged['weight_pred']))

    assert mae <= 1.0, f"MAE of edge weights is {mae:.4f}, which is greater than the threshold of 1.0"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
