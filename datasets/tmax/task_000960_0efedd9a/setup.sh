#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        sqlite3 \
        build-essential

    pip3 install pytest

    mkdir -p /app

    # Generate image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'REGEX: ERR-[0-9]{4}-[A-Z]{3}'" /app/regex_spec.png

    # Generate logs and truth
    cat << 'EOF' > /tmp/gen_logs.py
import json
import random

random.seed(42)
with open('/app/raw_logs.jsonl', 'w') as f, open('/app/.hidden_truth_ids.txt', 'w') as truth:
    val = 10.0
    for i in range(1, 1001):
        if random.random() < 0.1:
            sensor_val = None
        else:
            sensor_val = val + random.uniform(-1, 1)
            val = sensor_val

        is_anomaly = random.random() < 0.05
        if is_anomaly:
            msg = f"System error \\u0041lert: ERR-{random.randint(1000,9999)}-SYS"
            truth.write(f"{i}\n")
        else:
            msg = f"Normal log \\u2713 heartbeat"

        row = {"id": i, "timestamp": f"2023-10-01T12:{i//60:02d}:{i%60:02d}Z", "message": msg, "sensor_val": sensor_val}
        f.write(json.dumps(row) + "\n")
EOF
    python3 /tmp/gen_logs.py

    # Skeleton C file
    cat << 'EOF' > /app/json_cleaner.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    // TODO: Read JSONL, unescape unicode, impute missing sensor_val, output CSV
    printf("Not implemented yet.\n");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
