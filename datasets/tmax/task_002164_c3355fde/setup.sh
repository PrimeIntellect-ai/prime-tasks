#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_sensor_data.csv
timestamp,sensor_id,temperature,humidity,status
2023-01-01T00:00:00Z,S1,22.5,45.0,ACTIVE
2023-01-01T00:01:00Z,S2,,50.0,ACTIVE
2023-01-01T00:02:00Z,S1,23.1,105.0,ERROR
2023-01-01T00:03:00Z,S3,21.0,-5.0,ACTIVE
2023-01-01T00:04:00Z,S2,24.0,55.0,ACTIVE,EXTRA_COLUMN
2023-01-01T00:05:00Z,S1,,99.9,ACTIVE
2023-01-01T00:06:00Z,S3,19.5,40.0,ACTIVE
2023-01-01T00:07:00Z,S1,20.0,0.0,ACTIVE
2023-01-01T00:08:00Z,S2,22.0,100.0,ACTIVE
EOF

    cat << 'EOF' > /home/user/tune.py
import sys
import json
import csv

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    input_file = sys.argv[1]
    valid_rows = 0
    with open(input_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            valid_rows += 1

    # Dummy cross-validation/hyperparameter selection output
    # based on the number of processed rows
    best_alpha = 0.1 if valid_rows > 3 else 1.0

    with open('/home/user/best_model_metrics.json', 'w') as f:
        json.dump({"best_alpha": best_alpha, "rows_trained": valid_rows}, f)

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/tune.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
