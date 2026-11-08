#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
from collections import Counter

import numpy as np
import pandas as pd

OUTPUT_CSV = "/home/user/final_output.csv"
DB_PATH = "/home/user/system_metrics.db"
LOG_PATH = "/home/user/pipeline.log"
RAW_PATH = "/home/user/raw_metrics.csv"
TRUTH_CSV = "/tests/hidden_truth.csv"


def parse_timestamp(value):
    text = str(value).strip()
    if re.fullmatch(r"[+-]?\d+", text):
        return pd.to_datetime(int(text), unit="s", utc=True)
    return pd.to_datetime(text, utc=True)


def load_expected():
    raw = pd.read_csv(RAW_PATH, dtype={"timestamp": str})
    raw["parsed_timestamp"] = raw["timestamp"].map(parse_timestamp)

    corrupt = (raw["cpu_usage"] < 0) | (raw["memory_usage"] < 0)
    valid = raw.loc[~corrupt, ["parsed_timestamp", "cpu_usage", "memory_usage", "latency"]].copy()
    valid = valid.set_index("parsed_timestamp").sort_index()

    expected = valid.resample("1min").mean()
    expected[["cpu_usage", "memory_usage", "latency"]] = expected[
        ["cpu_usage", "memory_usage", "latency"]
    ].interpolate(method="linear")
    expected["normalized_latency"] = expected["latency"] - 45.2
    expected = expected.reset_index().rename(columns={"parsed_timestamp": "timestamp"})
    return raw, corrupt, expected


def test_final_files_exist():
    expected_files = [LOG_PATH, DB_PATH, OUTPUT_CSV]
    for file_path in expected_files:
        assert os.path.exists(file_path), f"Missing expected output file: {file_path}"
        assert os.path.isfile(file_path), f"Expected a file, but found something else: {file_path}"
        assert os.path.getsize(file_path) > 0, f"Output file is empty: {file_path}"


def test_pipeline_log_records_every_corrupt_row():
    raw, corrupt, _ = load_expected()
    expected_lines = Counter(
        f"[WARNING] Dropped corrupt row at {timestamp}"
        for timestamp in raw.loc[corrupt, "timestamp"]
    )

    with open(LOG_PATH, "r", encoding="utf-8") as handle:
        actual_lines = Counter(
            line.strip()
            for line in handle
            if line.strip().startswith("[WARNING] Dropped corrupt row at ")
        )

    assert actual_lines == expected_lines, "pipeline.log does not contain exactly one warning for every corrupt row"


def test_final_csv_has_complete_minute_range():
    _, _, expected = load_expected()
    agent = pd.read_csv(OUTPUT_CSV)

    assert list(agent.columns) == ["timestamp", "normalized_latency"], (
        "final_output.csv must contain only timestamp and normalized_latency"
    )
    assert len(agent) == len(expected), "final_output.csv does not cover the complete resampled range"
    assert not agent.isnull().any().any(), "final_output.csv contains missing values"

    parsed = agent["timestamp"].map(parse_timestamp)
    assert parsed.is_unique, "final_output.csv contains duplicate timestamps"
    assert parsed.tolist() == expected["timestamp"].tolist(), (
        "Timestamps do not exactly cover the earliest-to-latest valid range at 1-minute frequency"
    )

    values = pd.to_numeric(agent["normalized_latency"], errors="coerce").to_numpy(dtype=float)
    assert np.isfinite(values).all(), "normalized_latency contains non-numeric or non-finite values"


def test_database_table_exists_and_contains_cleaned_dataset():
    assert os.path.exists(DB_PATH), f"Database missing: {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cleaned_metrics';")
        table = cursor.fetchone()
        assert table is not None, "Table 'cleaned_metrics' not found in the database."
        database = pd.read_sql_query("SELECT * FROM cleaned_metrics", conn)
    finally:
        conn.close()

    required = {"timestamp", "cpu_usage", "memory_usage", "latency", "normalized_latency"}
    assert required.issubset(database.columns), "cleaned_metrics is missing required columns"

    _, _, expected = load_expected()
    assert len(database) == len(expected), "cleaned_metrics has the wrong number of rows"

    database = database.copy()
    database["timestamp"] = database["timestamp"].map(parse_timestamp)
    database = database.sort_values("timestamp").reset_index(drop=True)
    expected = expected.sort_values("timestamp").reset_index(drop=True)

    assert database["timestamp"].tolist() == expected["timestamp"].tolist(), (
        "cleaned_metrics timestamps do not match the complete resampled range"
    )
    for column in ["cpu_usage", "memory_usage", "latency", "normalized_latency"]:
        actual = pd.to_numeric(database[column], errors="coerce").to_numpy(dtype=float)
        wanted = expected[column].to_numpy(dtype=float)
        assert np.isfinite(actual).all(), f"cleaned_metrics.{column} contains invalid values"
        assert np.allclose(actual, wanted, rtol=1e-7, atol=1e-7), (
            f"cleaned_metrics.{column} does not contain the cleaned and interpolated values"
        )


def test_mse_threshold():
    assert os.path.exists(OUTPUT_CSV), f"Agent output missing: {OUTPUT_CSV}"
    assert os.path.exists(TRUTH_CSV), f"Truth file missing: {TRUTH_CSV}"

    try:
        agent_df = pd.read_csv(OUTPUT_CSV)
        truth_df = pd.read_csv(TRUTH_CSV)
        merged = pd.merge(truth_df, agent_df, on="timestamp", suffixes=("_true", "_agent"))

        assert not merged.empty, "Merged dataframe is empty. Timestamps may not align or formats are incorrect."
        assert len(merged) == len(agent_df), "Not every submitted timestamp was compared to the hidden truth"
        assert agent_df["timestamp"].is_unique, "Submitted timestamps must be unique"

        mse = np.mean(
            (merged["normalized_latency_true"] - merged["normalized_latency_agent"]) ** 2
        )
    except Exception as exc:
        mse = 9999.0
        assert False, f"Failed to compute MSE due to exception: {exc}"

    threshold = 2.5
    assert mse <= threshold, (
        f"MSE of normalized_latency is {mse}, which exceeds the threshold of {threshold}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
