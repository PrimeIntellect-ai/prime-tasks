#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
import pytest

def test_valid_stations_file():
    txt_path = "/home/user/valid_stations.txt"
    assert os.path.exists(txt_path), f"File {txt_path} is missing."

    with open(txt_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_stations = ["S1", "S3"]
    assert lines == expected_stations, f"Expected valid stations {expected_stations}, but got {lines}."

def test_final_training_sample():
    input_path = "/home/user/sensor_data.csv"
    output_path = "/home/user/final_training_sample.csv"

    assert os.path.exists(input_path), f"Input file {input_path} is missing, cannot verify."
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    # Compute expected output
    df_wide = pd.read_csv(input_path)

    stubs = ["S1", "S2", "S3", "S4"]
    dfs = []
    for s in stubs:
        temp_df = df_wide[["Date", f"{s}_T", f"{s}_H"]].copy()
        temp_df.columns = ["Date", "Temperature", "Humidity"]
        temp_df["Station"] = s
        dfs.append(temp_df)

    df_long = pd.concat(dfs, ignore_index=True)
    df_long = df_long[["Date", "Station", "Temperature", "Humidity"]]

    df_long["THI"] = df_long["Temperature"] + 0.5 * df_long["Humidity"]
    df_long = df_long.sort_values(["Station", "Date"])
    df_long["Temp_Rolling_3"] = df_long.groupby("Station")["Temperature"].transform(lambda x: x.rolling(3, min_periods=1).mean())

    valid_stations = []
    for s in stubs:
        s_df = df_long[df_long["Station"] == s]
        rule_a_fail = (s_df["Temperature"] < -40.0).any() or (s_df["Temperature"] > 60.0).any()
        missing_pct = s_df["THI"].isna().mean()
        rule_b_fail = missing_pct > 0.05
        if not (rule_a_fail or rule_b_fail):
            valid_stations.append(s)

    df_valid = df_long[df_long["Station"].isin(valid_stations)].copy()

    df_valid["Date"] = pd.to_datetime(df_valid["Date"])
    df_valid["Month"] = df_valid["Date"].dt.month

    # Stratified Sample
    sampled = df_valid.groupby(["Station", "Month"], group_keys=False).apply(lambda x: x.sample(n=2, random_state=42)).reset_index(drop=True)
    sampled["Date"] = sampled["Date"].dt.strftime("%Y-%m-%d")
    sampled = sampled.drop(columns=["Month"])
    sampled = sampled.sort_values(["Station", "Date"]).reset_index(drop=True)

    # Ensure columns match requirements
    expected_cols = ["Date", "Station", "Temperature", "Humidity", "THI", "Temp_Rolling_3"]
    sampled = sampled[expected_cols]

    # Load student output
    student_df = pd.read_csv(output_path)

    # Check columns
    assert list(student_df.columns) == expected_cols, f"Expected columns {expected_cols}, but got {list(student_df.columns)}"

    # Check row count
    assert len(student_df) == len(sampled), f"Expected {len(sampled)} rows, but got {len(student_df)}"

    # Compare dataframes
    pd.testing.assert_frame_equal(
        student_df.reset_index(drop=True), 
        sampled.reset_index(drop=True), 
        check_exact=False, 
        atol=1e-4,
        obj="Final Training Sample CSV"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
