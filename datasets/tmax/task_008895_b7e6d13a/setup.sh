#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas matplotlib

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/batch_stats.csv
batch_id,record_count,inference_time_ms
1,100,12.5
2,200,24.1
3,300,35.8
4,400,NaN
5,500,60.2
6,150,18.0
7,250,999999.0
8,350,42.1
9,450,54.9
10,50,6.1
EOF

    cat << 'EOF' > /home/user/etl_benchmark.py
import pandas as pd
import matplotlib.pyplot as plt
import json

def run_pipeline():
    # Load data
    df = pd.read_csv('/home/user/data/batch_stats.csv')

    # TODO: Handle missing values and outliers
    # Remove rows where inference_time_ms is NaN
    # Remove rows where inference_time_ms > 10000

    # Calculate metrics
    cov = df['record_count'].cov(df['inference_time_ms'])
    corr = df['record_count'].corr(df['inference_time_ms'])

    # Save metrics
    with open('/home/user/benchmark_results.json', 'w') as f:
        json.dump({"correlation": round(corr, 4), "covariance": round(cov, 4)}, f)

    # Plotting
    plt.plot(df['record_count'], df['inference_time_ms'], 'ro')
    plt.title('Inference Time vs Record Count')
    plt.show()
    plt.savefig('/home/user/benchmark_plot.png')

if __name__ == "__main__":
    run_pipeline()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
