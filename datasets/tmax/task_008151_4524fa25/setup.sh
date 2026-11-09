#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas matplotlib

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_data.py
import csv
import random
import math

random.seed(42)

def generate_adversarial_floats(target_sum, num_elements):
    # Generates numbers of varying magnitudes to induce floating point errors if summed naively
    vals = [target_sum]
    for _ in range(num_elements):
        # add zero in a convoluted way: +x, -x
        mag = random.uniform(1e8, 1e10)
        vals.append(mag)
        vals.append(-mag)

        # small numbers
        small = random.uniform(1e-10, 1e-8)
        vals.append(small)
        vals.append(-small)
    random.shuffle(vals)
    return vals

data_A = generate_adversarial_floats(150.123456789012345, 10000)
data_B = generate_adversarial_floats(150.123456789010000, 10000)

with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'category', 'value'])
    id_counter = 1

    combined = []
    for v in data_A:
        combined.append((id_counter, 'A', v))
        id_counter += 1
    for v in data_B:
        combined.append((id_counter, 'B', v))
        id_counter += 1

    random.shuffle(combined)
    writer.writerows(combined)
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
