#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random
import math

random.seed(42)

start_ts = 1600000000
end_ts = start_ts + 86400 # 24 hours

with open('/home/user/tm_metrics_wide.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp_sec', 'query_id', 'src_chars', 'lat_es', 'chars_es', 'lat_fr', 'chars_fr', 'lat_de', 'chars_de'])

    for q_id in range(1, 5001):
        ts = random.randint(start_ts, end_ts - 1)
        src = random.randint(10, 100)

        # Base latency around 100ms
        l_es = int(random.gauss(100, 10))
        l_fr = int(random.gauss(105, 12))
        l_de = int(random.gauss(110, 15))

        # Inject anomalies
        # FR anomaly around hour 15 (start_ts + 15*3600)
        if start_ts + 15*3600 <= ts < start_ts + 16*3600:
            l_fr = int(random.gauss(250, 20))

        # DE anomaly around hour 8
        if start_ts + 8*3600 <= ts < start_ts + 9*3600:
            l_de = int(random.gauss(280, 25))

        # Sometimes requests fail
        if random.random() < 0.05: l_es = -1
        if random.random() < 0.05: l_fr = -1
        if random.random() < 0.05: l_de = -1

        c_es = int(src * random.uniform(1.0, 1.2)) if l_es != -1 else -1
        c_fr = int(src * random.uniform(1.1, 1.3)) if l_fr != -1 else -1
        c_de = int(src * random.uniform(1.2, 1.5)) if l_de != -1 else -1

        writer.writerow([ts, q_id, src, l_es, c_es, l_fr, c_fr, l_de, c_de])
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
