#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import random
import math
import csv

os.makedirs('/home/user/sim_runs', exist_ok=True)

reference_data = []

for i in range(1, 21):
    run_dir = f'/home/user/sim_runs/run_{i}'
    os.makedirs(run_dir, exist_ok=True)

    # Create numbers that cause catastrophic cancellation if added sequentially
    # Large positive, large negative, and some small numbers
    numbers = [1e16, -1e16]
    small_numbers = [random.uniform(1.0, 100.0) for _ in range(50)]
    numbers.extend(small_numbers)

    # Shuffle to introduce order dependency for naive sums
    random.shuffle(numbers)

    # The exact mathematical sum
    exact_sum = math.fsum(numbers)
    reference_data.append((f'run_{i}', exact_sum))

    with open(os.path.join(run_dir, 'output.dat'), 'w') as f:
        for num in numbers:
            f.write(f'{num}\n')

with open('/home/user/reference.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['run_id', 'expected_sum'])
    for row in reference_data:
        writer.writerow(row)
"

    chmod -R 777 /home/user
