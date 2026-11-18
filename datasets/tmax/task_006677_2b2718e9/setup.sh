#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > requirements.txt
numpy
pandas
matplotlib
EOF

    cat << 'EOF' > data1.csv
x,y
1,2.1
2,3.9
3,6.1
4,8.2
5,10.1
EOF

    cat << 'EOF' > data2.csv
x,y
1,1.5
2,4.5
3,7.5
4,10.5
5,13.5
EOF

    cat << 'EOF' > data3.csv
x,y
1,-1.0
2,-2.1
3,-3.0
4,-4.1
5,-5.0
EOF

    cat << 'EOF' > model_eval.py
import sys
import time
import json
import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

def load_data(file_path):
    return pd.read_csv(file_path)

def train_model(x, y):
    coeffs = np.polyfit(x, y, 1)
    return coeffs

def predict(coeffs, x):
    return np.polyval(coeffs, x)

def main():
    if len(sys.argv) != 2:
        print("Usage: python model_eval.py <dataset.csv>")
        sys.exit(1)

    dataset_file = sys.argv[1]

    start_time = time.time()

    df = load_data(dataset_file)
    x = df['x'].values
    y = df['y'].values

    coeffs = train_model(x, y)

    y_pred = predict(coeffs, x)
    end_time = time.time()

    # Incorrect MSE
    mse = np.sum(y - y_pred) / len(y)

    inference_time = end_time - start_time

    plt.figure()
    plt.scatter(x, y, label='Data')
    plt.plot(x, y_pred, color='red', label='Fit')
    plt.legend()
    plt.savefig(f"plot_{dataset_file.split('.')[0]}.png")

    result = {
        "dataset": dataset_file,
        "mse": float(mse),
        "inference_time_sec": inference_time
    }

    with open("results.json", "w") as f:
        json.dump([result], f)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
