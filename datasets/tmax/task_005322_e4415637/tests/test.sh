#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import io
import math
import os
import re
import sqlite3

import cv2
import numpy as np
import pandas as pd
import pytest

VIDEO = "/app/tracking.mp4"
DB = "/home/user/tracking.db"
SQL = "/home/user/etl.sql"
CSV = "/home/user/smoothed_speeds.csv"


def expected_trajectory():
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), f"Could not open {VIDEO}."
    rows = []
    frame_id = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        mask = gray >= 180
        ys, xs = np.nonzero(mask)
        assert len(xs) > 0, f"No bright dot found in frame {frame_id}."
        rows.append((frame_id, float(xs.mean()), float(ys.mean())))
        frame_id += 1
    cap.release()
    assert rows, "Video contains no readable frames."

    df = pd.DataFrame(rows, columns=["frame_id", "x", "y"])
    dx = df["x"].diff()
    dy = df["y"].diff()
    df["distance"] = np.sqrt(dx * dx + dy * dy).fillna(0.0)
    df["moving_avg_distance"] = df["distance"].rolling(5, min_periods=1).mean()
    return df


@pytest.fixture(scope="session")
def expected():
    return expected_trajectory()


def assert_complete_frame_ids(df, expected, source):
    assert "frame_id" in df.columns, f"'frame_id' column missing from {source}."
    ids = pd.to_numeric(df["frame_id"], errors="coerce")
    assert ids.notna().all(), f"Non-numeric frame_id in {source}."
    assert np.isfinite(ids).all(), f"Non-finite frame_id in {source}."
    assert not ids.duplicated().any(), f"Duplicate frame_id values in {source}."
    assert len(df) == len(expected), f"{source} must contain exactly one row per video frame."
    assert set(ids.astype(int)) == set(expected["frame_id"]), f"{source} does not contain the complete frame_id set."
    assert np.allclose(ids, ids.astype(int)), f"Non-integer frame_id in {source}."


def normalize_result(df, expected, source):
    assert_complete_frame_ids(df, expected, source)
    return df.assign(frame_id=pd.to_numeric(df["frame_id"])).sort_values("frame_id").reset_index(drop=True)


def assert_speed_values(df, expected, source):
    df = normalize_result(df, expected, source)
    for col in ("distance", "moving_avg_distance"):
        assert col in df.columns, f"'{col}' column missing from {source}."
        df[col] = pd.to_numeric(df[col], errors="coerce")

    first_distance = df.loc[0, "distance"]
    assert pd.isna(first_distance) or abs(first_distance) <= 1e-9, f"First distance in {source} must be 0 or NULL."
    assert np.isfinite(df.loc[1:, "distance"]).all(), f"Invalid distance values in {source}."
    assert np.isfinite(df.loc[1:, "moving_avg_distance"]).all(), f"Invalid moving-average values in {source}."
    if not pd.isna(df.loc[0, "moving_avg_distance"]):
        assert np.isfinite(df.loc[0, "moving_avg_distance"]), f"Invalid first moving average in {source}."

    distance_mse = np.nanmean((df["distance"].to_numpy() - expected["distance"].to_numpy()) ** 2)
    moving_mse = np.nanmean((df["moving_avg_distance"].to_numpy() - expected["moving_avg_distance"].to_numpy()) ** 2)
    assert math.isfinite(distance_mse) and distance_mse <= 0.5, f"Distance MSE in {source} is {distance_mse}."
    assert math.isfinite(moving_mse) and moving_mse <= 0.5, f"MSE of moving_avg_distance in {source} is {moving_mse}, which exceeds 0.5."


def execute_sql_query(sql_text):
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        statement = ""
        last_result = None
        for line in sql_text.splitlines(True):
            statement += line
            if sqlite3.complete_statement(statement):
                stmt = statement.strip()
                statement = ""
                if not stmt:
                    continue
                cur = conn.execute(stmt)
                if cur.description is not None:
                    columns = [d[0] for d in cur.description]
                    last_result = pd.DataFrame(cur.fetchall(), columns=columns)
        if statement.strip():
            cur = conn.execute(statement)
            if cur.description is not None:
                columns = [d[0] for d in cur.description]
                last_result = pd.DataFrame(cur.fetchall(), columns=columns)
        assert last_result is not None, "etl.sql did not execute a result-producing query."
        return last_result
    finally:
        conn.close()


def test_database_and_table_exist_and_loaded(expected):
    assert os.path.isfile(DB), f"Database file {DB} does not exist."
    conn = sqlite3.connect(DB)
    try:
        table_exists = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='positions'").fetchone()
        assert table_exists is not None, "Table 'positions' does not exist in the database."
        info = conn.execute("PRAGMA table_info(positions)").fetchall()
        columns = {row[1].lower() for row in info}
        assert {"frame_id", "x", "y"}.issubset(columns), "positions must contain frame_id, x, and y columns."
        positions = pd.read_sql_query("SELECT frame_id, x, y FROM positions", conn)
    finally:
        conn.close()

    positions = normalize_result(positions, expected, "positions table")
    for col in ("x", "y"):
        positions[col] = pd.to_numeric(positions[col], errors="coerce")
        assert np.isfinite(positions[col]).all(), f"Invalid {col} coordinates in positions."
    coordinate_error = np.sqrt((positions["x"] - expected["x"]) ** 2 + (positions["y"] - expected["y"]) ** 2)
    assert (coordinate_error <= 1.5).all(), "The positions table does not contain coordinates extracted from every video frame."


def test_etl_sql_rewritten_and_executable(expected):
    assert os.path.isfile(SQL), f"SQL file {SQL} does not exist."
    sql_text = open(SQL, "r", encoding="utf-8").read()
    assert re.search(r"\bLAG\s*\(", sql_text, re.IGNORECASE), "etl.sql must use LAG to access the previous frame."
    assert re.search(r"\bAVG\s*\([^;]*?\)\s*OVER\b", sql_text, re.IGNORECASE | re.DOTALL), "etl.sql must use AVG(...) OVER (...) for the moving average."
    assert not re.search(r"\bCROSS\s+JOIN\b", sql_text, re.IGNORECASE), "etl.sql still contains a cross join."
    sql_result = execute_sql_query(sql_text)
    assert_speed_values(sql_result, expected, "etl.sql result")


def test_smoothed_speeds_csv_and_mse(expected):
    assert os.path.isfile(CSV), f"Output file {CSV} does not exist."
    try:
        agent_df = pd.read_csv(CSV)
    except Exception as exc:
        pytest.fail(f"Failed to read {CSV}: {exc}")
    assert "frame_id" in agent_df.columns, "'frame_id' column missing from output CSV."
    assert "distance" in agent_df.columns, "'distance' column missing from output CSV."
    assert "moving_avg_distance" in agent_df.columns, "'moving_avg_distance' column missing from output CSV."
    assert_speed_values(agent_df, expected, "output CSV")
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
