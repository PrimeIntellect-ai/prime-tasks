#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
timestamp,sensor_a,sensor_b,sensor_c
2023-01-01T00:00,1.0,2.0,0.5
2023-01-01T01:00,1.2,2.1,0.6
2023-01-01T02:00,0.9,1.9,0.7
2023-01-01T03:00,ERR,2.5,0.8
2023-01-01T04:00,3.0,4.0,0.9
2023-01-01T05:00,3.5,4.5,1.0
2023-01-01T06:00,4.0,5.0,1.1
2023-01-01T07:00,3.8,4.1,1.5
2023-01-01T08:00,ERR,ERR,1.2
2023-01-01T09:00,1.0,1.0,0.5
2023-01-01T10:00,5.0,1.0,2.0
2023-01-01T11:00,1.0,5.0,0.1
EOF

    cat << 'EOF' > /home/user/model_spec.txt
Anomaly Score Model v1.0
The anomaly score is calculated as a linear combination of the current sensor_c reading and the rolling covariance of sensor_a and sensor_b.
Formula:
anomaly_score = (2.5 * sensor_c) + (1.5 * rolling_cov_a_b)
EOF

    cat << 'EOF' > /home/user/analyze.py
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

def load_and_clean_data(filepath):
    df = pd.read_csv(filepath)
    # TODO: Enforce schema (drop rows with 'ERR' in sensor columns, ensure floats)
    return df

def calculate_rolling_cov(df):
    # TODO: Calculate rolling covariance of sensor_a and sensor_b (window=3)
    # Fill first two rows with 0.0
    df['rolling_cov_a_b'] = 0.0
    return df

def apply_model(df):
    # TODO: Implement formula from model_spec.txt
    df['anomaly_score'] = 0.0
    return df

def plot_anomalies(df):
    plt.figure(figsize=(10, 5))
    plt.plot(df['timestamp'], df['anomaly_score'], marker='o')
    plt.title("Anomaly Scores")
    plt.xlabel("Timestamp")
    plt.ylabel("Score")
    # This crashes on a headless server!
    plt.show()

if __name__ == "__main__":
    df = load_and_clean_data('/home/user/raw_data.csv')
    df = calculate_rolling_cov(df)
    df = apply_model(df)
    plot_anomalies(df)

    # TODO: Save top 3 anomalies to /home/user/top_anomalies.json
EOF

    chmod -R 777 /home/user
