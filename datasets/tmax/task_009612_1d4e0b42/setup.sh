#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/setup.py
import csv
import random
import math

random.seed(42)

def generate_csv(filename, n_rows):
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'x', 'y', 'z'])
        for i in range(1, n_rows + 1):
            x = random.uniform(-100, 100)
            y = random.uniform(-100, 100)
            z = random.uniform(-100, 100)
            writer.writerow([i, f"{x:.4f}", f"{y:.4f}", f"{z:.4f}"])

generate_csv('/home/user/sensors_A.csv', 50)
generate_csv('/home/user/sensors_B.csv', 75)

# Generate golden truth
def read_csv(filename):
    data = {}
    with open(filename, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data[int(row['id'])] = (float(row['x']), float(row['y']), float(row['z']))
    return data

data_a = read_csv('/home/user/sensors_A.csv')
data_b = read_csv('/home/user/sensors_B.csv')

with open('/home/user/expected_matches.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id_A', 'id_B', 'distance'])
    for id_a in sorted(data_a.keys()):
        pt_a = data_a[id_a]
        min_dist = float('inf')
        best_b = -1
        for id_b, pt_b in data_b.items():
            dist = math.sqrt((pt_a[0]-pt_b[0])**2 + (pt_a[1]-pt_b[1])**2 + (pt_a[2]-pt_b[2])**2)
            if dist < min_dist:
                min_dist = dist
                best_b = id_b
            elif dist == min_dist and id_b < best_b:
                best_b = id_b
        writer.writerow([id_a, best_b, f"{min_dist:.4f}"])
EOF

python3 /home/user/setup.py

chmod -R 777 /home/user
