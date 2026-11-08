#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pandas as pd
import numpy as np
import pytest


def build_reference():
    data_csv = {
        'Date': pd.to_datetime(['2023-01-01', '2023-01-02', '2023-01-05', '2023-01-10']),
        'Temp_London': [6.0, 5.5, 4.0, 3.0],
        'Temp_Moscow': [-2.0, -3.0, -5.0, -8.0],
        'Temp_Tokyo': [10.0, np.nan, 8.0, 5.0]
    }
    df_csv = pd.DataFrame(data_csv)
    df_long = df_csv.melt(id_vars=['Date'], var_name='City', value_name='Temperature')
    df_long['City'] = df_long['City'].str.replace('Temp_', '', regex=False)

    data_ocr = {
        'Date': pd.to_datetime(['2023-01-04'] * 3),
        'City': ['Moscow', 'Tokyo', 'London'],
        'Temperature': [-4.5, 9.2, 5.0]
    }
    df_ocr = pd.DataFrame(data_ocr)

    df_combined = pd.concat([df_long, df_ocr]).dropna(subset=['Temperature'])
    df_combined = df_combined.groupby(['Date', 'City']).mean().reset_index()
    df_combined.set_index('Date', inplace=True)

    df_resampled = df_combined.groupby('City').resample('D').asfreq()
    if 'City' in df_resampled.columns:
        df_resampled = df_resampled.drop(columns=['City'])
    df_resampled = df_resampled.reset_index(level='City')
    df_resampled['Temperature'] = df_resampled.groupby('City')['Temperature'].transform(
        lambda x: x.interpolate(method='linear')
    )
    df_resampled = df_resampled.reset_index()
    df_resampled = df_resampled[
        (df_resampled['Date'] >= '2023-01-01') &
        (df_resampled['Date'] <= '2023-01-10')
    ]
    return df_resampled.sort_values(['Date', 'City']).reset_index(drop=True)


def test_clean_weather_parquet_mse():
    agent_path = '/app/clean_weather.parquet'
    assert os.path.exists(agent_path), f"Agent output file not found: {agent_path}"

    try:
        agent_df = pd.read_parquet(agent_path)
    except Exception as e:
        pytest.fail(f"Failed to read agent parquet file: {e}")

    ref_df = build_reference()

    expected_cols = ['Date', 'City', 'Temperature']
    for col in expected_cols:
        assert col in agent_df.columns, (
            f"Missing column '{col}' in agent output. "
            f"Found columns: {agent_df.columns.tolist()}"
        )

    agent_df['Date'] = pd.to_datetime(agent_df['Date'])
    ref_df['Date'] = pd.to_datetime(ref_df['Date'])

    agent_df = agent_df.sort_values(['Date', 'City']).reset_index(drop=True)
    ref_df = ref_df.sort_values(['Date', 'City']).reset_index(drop=True)

    assert len(agent_df) == len(ref_df), (
        f"Expected {len(ref_df)} rows, but got {len(agent_df)} rows."
    )

    pd.testing.assert_series_equal(
        agent_df['Date'],
        ref_df['Date'],
        check_names=False,
        obj='Date column'
    )
    pd.testing.assert_series_equal(
        agent_df['City'].astype(str),
        ref_df['City'].astype(str),
        check_names=False,
        obj='City column'
    )

    mse = np.mean((agent_df['Temperature'] - ref_df['Temperature']) ** 2)
    assert mse <= 0.1, (
        f"MSE is {mse:.4f}, which is greater than the threshold of 0.1."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
