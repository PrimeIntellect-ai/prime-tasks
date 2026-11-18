#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq parallel gawk sed grep
pip3 install pytest

mkdir -p /home/user/data

python3 -c "
import os
import csv
import json
import random

random.seed(42)

data_dir = '/home/user/data'
os.makedirs(data_dir, exist_ok=True)

ground_truth = {}

for i in range(1, 21):
    filename = f'sensor_{i}.csv'
    filepath = os.path.join(data_dir, filename)

    sum_of_squares = 0
    with open(filepath, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'timestamp', 'reading'])

        # 100 to 500 rows per file
        num_rows = random.randint(100, 500)
        for row_idx in range(num_rows):
            reading = random.randint(0, 100)
            writer.writerow([row_idx, f'2023-10-01T12:{row_idx%60:02d}:00Z', reading])

            if reading % 2 != 0:
                sum_of_squares += (reading * reading)

    ground_truth[filename] = sum_of_squares

# Save ground truth for verification suite
with open('/home/user/.truth.json', 'w') as f:
    json.dump(ground_truth, f)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
