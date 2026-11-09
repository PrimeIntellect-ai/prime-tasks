#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import random
import math

random.seed(42)

vectors = {}
for i in range(1, 1001):
    item_id = f"item_{i}"
    if i == 842:
        item_id = "target_842"
    v = [random.uniform(0, 10) for _ in range(5)]
    vectors[item_id] = v

# Write to file
with open("/home/user/vectors.csv", "w") as f:
    for item_id, v in vectors.items():
        v_str = ",".join(f"{x:.4f}" for x in v)
        f.write(f"{item_id},{v_str}\n")

# Calculate ground truth
target_v = vectors["target_842"]
distances = []
for item_id, v in vectors.items():
    if item_id == "target_842":
        continue
    dist = math.sqrt(sum((target_v[j] - v[j])**2 for j in range(5)))
    distances.append((dist, item_id))

distances.sort()
top5 = [x[1] for x in distances[:5]]

with open("/home/user/expected_top5.txt", "w") as f:
    for item_id in top5:
        f.write(f"{item_id}\n")
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
