#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk cron
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data/raw
    mkdir -p /home/user/data/processed
    mkdir -p /app/awk-ts-tools-1.0

    # Generate data
    python3 -c "
import os
import math
import random

start_t = 1600000000
end_t = start_t + 3600

# Ground truth
with open('/tmp/ground_truth.csv', 'w') as f:
    for t in range(start_t, end_t + 1, 60):
        temp = math.sin((t - start_t) / 3600.0 * 2 * math.pi) * 10 + 20
        f.write(f'{t},{temp:.4f}\n')

# Raw data
raw_points = []
# Ensure start and end are present
raw_points.append((start_t, 20.0))
for t in range(start_t + 15, end_t, 15):
    if random.random() > 0.4:
        temp = math.sin((t - start_t) / 3600.0 * 2 * math.pi) * 10 + 20 + random.uniform(-0.05, 0.05)
        raw_points.append((t, temp))
raw_points.append((end_t, 20.0))

chunk_size = len(raw_points) // 3
for i in range(3):
    chunk = raw_points[i*chunk_size : (i+1)*chunk_size if i < 2 else len(raw_points)]
    with open(f'/home/user/data/raw/sensor_{i}.csv', 'w', encoding='iso-8859-1') as f:
        for t, temp in chunk:
            f.write(f'{t},{temp:.4f}\n')
"

    # Create vendored toolkit
    cat << 'EOF' > /app/awk-ts-tools-1.0/interpolate.awk
#!/usr/bin/awk -f
BEGIN { FS=","; OFS="," }
NR==1 {
    prev_t = $1
    prev_temp = $2
    print prev_t, prev_temp
    next
}
{
    curr_t = $1
    curr_temp = $2

    while (curr_t - prev_t > 60) {
        target_t = prev_t + 60
        x1 = prev_t; y1 = prev_temp
        x2 = curr_t; y2 = curr_temp

        # Buggy slope calculation
        slope = (y2 + y1) / (x2 - x1)

        interp_y = y1 + slope * (target_t - x1)
        print target_t, interp_y

        prev_t = target_t
        prev_temp = interp_y
    }

    if (curr_t - prev_t == 60) {
        print curr_t, curr_temp
        prev_t = curr_t
        prev_temp = curr_temp
    } else {
        prev_t = curr_t
        prev_temp = curr_temp
    }
}
EOF
    chmod +x /app/awk-ts-tools-1.0/interpolate.awk

    cat << 'EOF' > /app/awk-ts-tools-1.0/Makefile
AWK_BIN=/usr/local/bin/nonexistent-awk

run:
	$(AWK_BIN) -f interpolate.awk
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
