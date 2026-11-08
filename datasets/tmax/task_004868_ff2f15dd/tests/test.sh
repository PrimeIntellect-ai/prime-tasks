#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error


def combined_data():
    df1 = pd.read_csv('/home/user/data/batch_1.csv')
    df2 = pd.read_csv('/home/user/data/batch_2.csv')
    return pd.concat([df1, df2])


def test_agg_results():
    user_file = '/home/user/agg_results.csv'
    assert os.path.exists(user_file), f"Expected file {user_file} does not exist."

    with open(user_file, 'r') as f:
        user_content = f.read().strip().splitlines()

    df_combined = combined_data()
    agg = df_combined.groupby('sensor_id')['temperature'].mean().reset_index()
    agg.rename(columns={'temperature': 'avg_temperature'}, inplace=True)
    agg['avg_temperature'] = agg['avg_temperature'].round(2)
    expected_content = agg.sort_values('sensor_id').to_csv(index=False).strip().splitlines()

    assert user_content == expected_content, f"Content of {user_file} does not match expected output."


def test_model_metrics():
    user_file = '/home/user/model_metrics.txt'
    assert os.path.exists(user_file), f"Expected file {user_file} does not exist."

    with open(user_file, 'r') as f:
        user_content = f.read().strip()

    df_combined = combined_data()
    X = df_combined[['temperature', 'humidity']]
    y = df_combined['pressure']
    model = LinearRegression()
    model.fit(X, y)
    preds = model.predict(X)
    rmse = np.sqrt(mean_squared_error(y, preds))
    expected_content = f"{rmse:.4f}"

    assert user_content == expected_content, f"Content of {user_file} does not match expected output. Expected '{expected_content}', got '{user_content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
