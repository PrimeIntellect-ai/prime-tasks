#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv strace
    pip3 install pytest

    mkdir -p /home/user/ticket_4092

    cat << 'EOF' > /home/user/ticket_4092/requirements.txt
numpy==1.19.0
pandas==2.1.0
EOF

    cat << 'EOF' > /home/user/ticket_4092/prices.csv
Date,Price
2023-01-01,100.0
2023-01-02,101.5
2023-01-03,CORRUPTED_DATA
2023-01-04,103.0
2023-01-05,102.5
2023-01-06,ERR_TIMEOUT
2023-01-07,105.2
EOF

    cat << 'EOF' > /home/user/ticket_4092/pricing.py
import os
import math
import pandas as pd
import numpy as np

def get_calibration_factor():
    try:
        # Deliberately swallowing the error so strace is needed
        with open('/home/user/ticket_4092/.calib_secret_v2', 'r') as f:
            return float(f.read().strip())
    except Exception:
        return 0.0

def calculate_volatility(prices):
    if len(prices) < 2:
        return 0.0

    returns = []
    for i in range(1, len(prices)):
        # BUG: Missing math.log here
        u_i = prices[i] / prices[i-1]
        returns.append(u_i)

    mean_return = sum(returns) / len(returns)
    variance = sum((u - mean_return)**2 for u in returns) / (len(returns) - 1)

    # Annualized volatility assuming 252 trading days
    return math.sqrt(variance * 252)

def main():
    df = pd.read_csv('/home/user/ticket_4092/prices.csv')

    clean_prices = []
    valid_dates = []

    for index, row in df.iterrows():
        # BUG: No error handling for corrupted float
        val = float(row['Price'])
        clean_prices.append(val)
        valid_dates.append(row['Date'])

    volatility = calculate_volatility(clean_prices)
    calib = get_calibration_factor()

    final_volatility = volatility * calib

    # Write outputs
    out_df = pd.DataFrame({'Date': valid_dates, 'CleanPrice': clean_prices})
    out_df.to_csv('/home/user/ticket_4092/clean_results.csv', index=False)

    with open('/home/user/ticket_4092/clean_results.csv', 'a') as f:
        f.write(f"# FINAL_CALIBRATED_VOLATILITY: {final_volatility:.6f}\n")

if __name__ == '__main__':
    main()
EOF

    chmod +x /home/user/ticket_4092/pricing.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
