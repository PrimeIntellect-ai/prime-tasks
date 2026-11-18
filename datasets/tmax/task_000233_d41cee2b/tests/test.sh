#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest
import pandas as pd
import numpy as np

EXPECTED_COLUMNS = {'time', 'sensor', 'value'}
EXPECTED_KEYS = pd.MultiIndex.from_product(
    [[0, 10, 20, 30, 40, 50, 60], ['Alpha', 'Beta']],
    names=['time', 'sensor']
)


def assert_complete_long_format(df, csv_path):
    assert set(df.columns) == EXPECTED_COLUMNS, \
        f"Columns in {csv_path} must be exactly {EXPECTED_COLUMNS}, got {set(df.columns)}"
    assert len(df) == 14, f"{csv_path} must contain exactly 14 rows, got {len(df)}"
    assert not df[['time', 'sensor']].isna().any().any(), \
        f"{csv_path} contains null time or sensor keys"
    assert not df.duplicated(['time', 'sensor']).any(), \
        f"{csv_path} contains duplicate time/sensor rows"
    actual_keys = pd.MultiIndex.from_frame(df[['time', 'sensor']])
    missing = EXPECTED_KEYS.difference(actual_keys)
    extra = actual_keys.difference(EXPECTED_KEYS)
    assert len(missing) == 0 and len(extra) == 0, \
        f"{csv_path} must contain every expected time/sensor pair exactly once; missing={list(missing)}, extra={list(extra)}"


def test_parsed_telemetry_exists_and_format():
    """Check that the transcription was reshaped completely, including source nulls."""
    csv_path = "/home/user/parsed_telemetry.csv"
    assert os.path.exists(csv_path), f"File {csv_path} does not exist."

    df = pd.read_csv(csv_path)
    assert_complete_long_format(df, csv_path)
    indexed = df.set_index(['time', 'sensor'])['value']

    expected = {
        (0, 'Alpha'): 12.0, (0, 'Beta'): 50.0,
        (10, 'Alpha'): 14.5, (10, 'Beta'): 48.2,
        (20, 'Alpha'): None, (20, 'Beta'): 47.0,
        (30, 'Alpha'): 17.5, (30, 'Beta'): None,
        (40, 'Alpha'): 18.0, (40, 'Beta'): 45.0,
        (50, 'Alpha'): 19.5, (50, 'Beta'): 44.5,
        (60, 'Alpha'): 20.0, (60, 'Beta'): 44.0,
    }
    for key, expected_value in expected.items():
        actual = indexed.loc[key]
        if expected_value is None:
            assert pd.isna(actual), f"Parsed value for {key} must be missing, got {actual!r}"
        else:
            try:
                actual_number = float(actual)
            except (TypeError, ValueError):
                pytest.fail(f"Parsed value for {key} is not numeric: {actual!r}")
            assert np.isfinite(actual_number) and abs(actual_number - expected_value) <= 1e-6, \
                f"Parsed value for {key} was {actual_number}, expected {expected_value}"


def test_imputed_telemetry_mse():
    """Calculate the MSE and require the complete imputed long-format dataset."""
    csv_path = "/home/user/imputed_telemetry.csv"
    assert os.path.exists(csv_path), f"File {csv_path} does not exist."

    expected_df = pd.DataFrame({
        'time': [0, 0, 10, 10, 20, 20, 30, 30, 40, 40, 50, 50, 60, 60],
        'sensor': ['Alpha', 'Beta'] * 7,
        'value': [12.0, 50.0, 14.5, 48.2, 16.0, 47.0, 17.5, 46.0, 18.0, 45.0, 19.5, 44.5, 20.0, 44.0]
    })

    try:
        agent_df = pd.read_csv(csv_path)
        assert_complete_long_format(agent_df, csv_path)
        agent_df.columns = [c.lower() for c in agent_df.columns]
        agent_df['value'] = pd.to_numeric(agent_df['value'], errors='raise')
        assert np.isfinite(agent_df['value']).all(), "Imputed values must all be finite numbers"

        merged = pd.merge(
            expected_df, agent_df, on=['time', 'sensor'],
            suffixes=('_expected', '_actual'), validate='one_to_one'
        )
        assert len(merged) == 14, "Imputed dataset did not match all 14 expected rows"
        mse = np.mean((merged['value_expected'] - merged['value_actual']) ** 2)
    except AssertionError:
        raise
    except Exception as e:
        pytest.fail(f"Failed to process {csv_path} for MSE calculation: {e}")

    assert mse <= 0.1, f"MSE {mse} exceeded threshold 0.1 for imputed values."


def test_summary_json():
    """Check that summary means are correct and agree with the complete imputed data."""
    json_path = "/home/user/summary.json"
    assert os.path.exists(json_path), f"File {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert "Alpha" in summary, "Key 'Alpha' missing in summary JSON."
    assert "Beta" in summary, "Key 'Beta' missing in summary JSON."
    assert "mean" in summary["Alpha"], "Key 'mean' missing in summary['Alpha']."
    assert "mean" in summary["Beta"], "Key 'mean' missing in summary['Beta']."

    expected_alpha_mean = np.mean([12.0, 14.5, 16.0, 17.5, 18.0, 19.5, 20.0])
    expected_beta_mean = np.mean([50.0, 48.2, 47.0, 46.0, 45.0, 44.5, 44.0])

    agent_alpha_mean = summary["Alpha"]["mean"]
    agent_beta_mean = summary["Beta"]["mean"]

    assert abs(agent_alpha_mean - expected_alpha_mean) <= 0.5, \
        f"Alpha mean {agent_alpha_mean} is too far from expected {expected_alpha_mean}"
    assert abs(agent_beta_mean - expected_beta_mean) <= 0.5, \
        f"Beta mean {agent_beta_mean} is too far from expected {expected_beta_mean}"

    imputed = pd.read_csv('/home/user/imputed_telemetry.csv')
    assert_complete_long_format(imputed, '/home/user/imputed_telemetry.csv')
    imputed['value'] = pd.to_numeric(imputed['value'], errors='raise')
    actual_means = imputed.groupby('sensor')['value'].mean()
    assert abs(float(agent_alpha_mean) - actual_means['Alpha']) <= 1e-6, \
        "Alpha summary mean does not equal the mean of the imputed dataset"
    assert abs(float(agent_beta_mean) - actual_means['Beta']) <= 1e-6, \
        "Beta summary mean does not equal the mean of the imputed dataset"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
