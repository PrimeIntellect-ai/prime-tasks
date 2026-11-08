#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random
import csv

os.makedirs('/home/user/configs', exist_ok=True)

random.seed(42)

servers = [f"srv_{i:03d}" for i in range(1, 201)]
keys = [f"key_{j:03d}" for j in range(1, 51)]

day1_data = {}
day2_data = {}

# Generate base data
for srv in servers:
    for key in keys:
        if random.random() > 0.2: # 80% chance to have a key
            val = str(random.randint(100, 999))
            day1_data[(srv, key)] = val

            # Decide what happens in day2
            action = random.random()
            if action < 0.1:
                # Deleted in day2 -> do not add to day2_data
                pass
            elif action < 0.3:
                # Modified
                day2_data[(srv, key)] = str(random.randint(1000, 9999))
            else:
                # Unchanged
                day2_data[(srv, key)] = val

# Add some new keys in day2
for srv in servers:
    for key in keys:
        if (srv, key) not in day1_data:
            if random.random() > 0.5:
                day2_data[(srv, key)] = str(random.randint(10, 99))

# Write files, shuffled to require sorting
def write_dict_to_csv(d, filepath):
    items = list(d.items())
    random.shuffle(items)
    with open(filepath, 'w', newline='') as f:
        writer = csv.writer(f)
        for (s, k), v in items:
            writer.writerow([s, k, v])

write_dict_to_csv(day1_data, '/home/user/configs/day1.csv')
write_dict_to_csv(day2_data, '/home/user/configs/day2.csv')

# Generate expected golden output for verification
expected_output = []
all_keys = set(day1_data.keys()).union(set(day2_data.keys()))

for (srv, key) in all_keys:
    val1 = day1_data.get((srv, key))
    val2 = day2_data.get((srv, key))

    if val1 is not None and val2 is None:
        expected_output.append([srv, key, 'DELETED', val1, ''])
    elif val1 is None and val2 is not None:
        expected_output.append([srv, key, 'ADDED', '', val2])
    elif val1 is not None and val2 is not None and val1 != val2:
        expected_output.append([srv, key, 'MODIFIED', val1, val2])

# Sort expected output
expected_output.sort(key=lambda x: (x[0], x[1]))

with open('/home/user/.expected_delta.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(expected_output)

EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user/configs
    chmod -R 777 /home/user
