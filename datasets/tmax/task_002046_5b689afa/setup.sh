#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow

    mkdir -p /home/user

    # Create the raw data file
    cat << 'EOF' > /home/user/raw_data.csv
id,feature_a,click_count
1,0.5,10
2,0.8,
3,0.1,5
EOF

    # Create the broken ETL pipeline script
    cat << 'EOF' > /home/user/etl_pipeline.py
import pandas as pd

def process_data():
    df = pd.read_csv('/home/user/raw_data.csv')
    # Missing schema enforcement for click_count
    df.to_parquet('/home/user/processed_data.parquet', index=False)

if __name__ == "__main__":
    process_data()
EOF

    # Create the benchmarking script
    cat << 'EOF' > /home/user/benchmark.py
import pandas as pd
import time
import json
import sys

def run_inference():
    try:
        df = pd.read_parquet('/home/user/processed_data.parquet')
    except Exception as e:
        print(f"Failed to read parquet: {e}")
        sys.exit(1)

    # Enforce strict schema validation
    dtype_str = str(df['click_count'].dtype)
    if dtype_str != 'Int64':
        print(f"Schema enforcement failed: click_count is {dtype_str}, expected Int64")
        sys.exit(1)

    start_time = time.time()
    # Simulate inference latency
    time.sleep(0.1)
    duration = time.time() - start_time

    metrics = {
        "status": "success",
        "inference_time_sec": duration,
        "model_version": "v1.2",
        "experiment_id": "exp_773",
        "records_processed": len(df)
    }

    with open('/home/user/experiment_results.json', 'w') as f:
        json.dump(metrics, f)
    print("Benchmarking completed successfully.")

if __name__ == "__main__":
    run_inference()
EOF

    chmod +x /home/user/etl_pipeline.py
    chmod +x /home/user/benchmark.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
