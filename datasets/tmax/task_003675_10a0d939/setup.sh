#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/corpora/evil /app/corpora/clean

    # Create and compile the fake_metric_gen binary
    cat << 'EOF' > /app/fake_metric_gen.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    long long ts = atoll(argv[1]);
    long long uid = atoll(argv[2]);
    long long res = (ts ^ uid) % 9973;
    printf("%lld\n", res);
    return 0;
}
EOF

    gcc -O2 /app/fake_metric_gen.c -o /app/fake_metric_gen
    strip /app/fake_metric_gen
    rm /app/fake_metric_gen.c

    # Generate corpora
    cat << 'EOF' > /app/generate_corpora.py
import csv
import random
from datetime import datetime, timezone, timedelta

def generate_csv(path, is_evil, num_rows=1000):
    start_time = datetime(2023, 1, 1, tzinfo=timezone.utc)
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp_iso', 'user_id', 'metric_value'])

        for _ in range(num_rows):
            dt = start_time + timedelta(seconds=random.randint(0, 31536000))
            ts = int(dt.timestamp())
            uid = random.randint(1000, 9999)
            evil_val = (ts ^ uid) % 9973

            if is_evil:
                val = evil_val
            else:
                val = evil_val + random.randint(1, 1000)
                if val == evil_val:
                    val += 1

            writer.writerow([dt.isoformat().replace('+00:00', 'Z'), uid, val])

generate_csv('/app/corpora/evil/evil_1.csv', True)
generate_csv('/app/corpora/clean/clean_1.csv', False)
EOF

    python3 /app/generate_corpora.py
    rm /app/generate_corpora.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
