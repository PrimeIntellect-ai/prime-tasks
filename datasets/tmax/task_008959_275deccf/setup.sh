#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import csv
import math
import json

data = [
    ["id", "val_x", "val_y"],
    ["1", "10.5", "20.1"],
    ["2", "11.0", "21.0"],
    ["3", "NA", "22.3"],
    ["4", "12.5", "23.5"],
    ["5", "bad", "24.0"],
    ["6", "14.0", "25.8"],
    ["7", "15.1", "26.2"],
    ["8", "16.5", "28.1"],
    ["9", "17.2", "error"],
    ["10", "18.0", "30.5"]
]

with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)

# Ground truth calculations
valid_x = [10.5, 11.0, 12.5, 14.0, 15.1, 16.5, 18.0]
valid_y = [20.1, 21.0, 23.5, 25.8, 26.2, 28.1, 30.5]
n = len(valid_x)

mean_x = sum(valid_x) / n
mean_y = sum(valid_y) / n

# Sample StdDev
var_x = sum((x - mean_x)**2 for x in valid_x) / (n - 1)
stddev_x = math.sqrt(var_x)

# Covariance
covar = sum((x - mean_x)*(y - mean_y) for x, y in zip(valid_x, valid_y)) / (n - 1)
var_y = sum((y - mean_y)**2 for y in valid_y) / (n - 1)
stddev_y = math.sqrt(var_y)

correlation = covar / (stddev_x * stddev_y)

ci_lower_x = mean_x - 1.96 * (stddev_x / math.sqrt(n))
ci_upper_x = mean_x + 1.96 * (stddev_x / math.sqrt(n))

expected_json = {
    "correlation": round(correlation, 4),
    "mean_x": round(mean_x, 4),
    "ci_lower_x": round(ci_lower_x, 4),
    "ci_upper_x": round(ci_upper_x, 4)
}

with open('/home/user/expected_metrics.json', 'w') as f:
    json.dump(expected_json, f, indent=2)

EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    mkdir -p /home/user/sensor_project

    chmod -R 777 /home/user
