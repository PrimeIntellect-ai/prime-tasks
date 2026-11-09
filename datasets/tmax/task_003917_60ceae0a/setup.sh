#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import csv
import random

random.seed(42)

# Train data (mean ~ 50, std ~ 10)
with open('train.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'feature_A', 'feature_B'])
    for i in range(1, 101):
        writer.writerow([f'tr_{i:03d}', round(random.gauss(50, 10), 2), round(random.uniform(0, 1), 2)])

# Test data (mean ~ 60, std ~ 15 - deliberately different to test leakage)
test_ids = [f'ts_{i:03d}' for i in range(1, 51)]
test_features = []
with open('test.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'feature_A', 'feature_B'])
    for tid in test_ids:
        val = round(random.gauss(60, 15), 2)
        test_features.append(val)
        writer.writerow([tid, val, round(random.uniform(0, 1), 2)])

# Labels (synthetic relationship: label ~ Z + noise)
# First compute actual train mean and std to ensure deterministic labels
train_vals = []
with open('train.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        train_vals.append(float(row['feature_A']))

train_mean = sum(train_vals) / len(train_vals)
train_variance = sum((x - train_mean) ** 2 for x in train_vals) / (len(train_vals) - 1)
train_std = train_variance ** 0.5

with open('labels.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'label'])
    for tid, val in zip(test_ids, test_features):
        z = (val - train_mean) / train_std
        label = round(z + random.gauss(0, 0.5), 4)
        writer.writerow([tid, label])
EOF

    python3 generate_data.py
    rm generate_data.py

    awk -F, 'NR>1 {sum+=$2; count++} END {print sum/count}' train.csv > train_mean.tmp
    awk -F, -v m=$(cat train_mean.tmp) 'NR>1 {sum+=($2-m)^2; count++} END {print sqrt(sum/(count-1))}' train.csv > train_std.tmp

    tail -n +2 test.csv | sort -t, -k1,1 > test_sorted.tmp
    tail -n +2 labels.csv | sort -t, -k1,1 > labels_sorted.tmp

    join -t, -1 1 -2 1 test_sorted.tmp labels_sorted.tmp > joined.tmp

    awk -F, -v m=$(cat train_mean.tmp) -v s=$(cat train_std.tmp) '
    {
        z = ($2 - m) / s
        label = $4
        diff = z - label
        sum_sq += diff * diff
        count++
    }
    END {
        printf "%.4f\n", sum_sq / count
    }' joined.tmp > expected_mse.txt

    rm *.tmp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
