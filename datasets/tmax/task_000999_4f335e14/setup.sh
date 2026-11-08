#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        redis-tools \
        g++ \
        libcurl4-openssl-dev \
        libhiredis-dev \
        bc \
        curl \
        jq \
        psmisc

    pip3 install pytest flask redis

    mkdir -p /app/services /app/raw_data /app/scripts /app/organized_data

    cat << 'EOF' > /app/services/flask_app.py
from flask import Flask, jsonify
app = Flask(__name__)
@app.route('/rules')
def rules():
    return jsonify({"target_dir": "/app/organized_data", "prefix": "clean"})
if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/services/sensor_simulator.py
import os
import time
import struct
import random
import fcntl

os.makedirs('/app/raw_data', exist_ok=True)
sensor_id = 0
while True:
    d = f'/app/raw_data/station_{random.randint(1,5)}/day_{random.randint(1,5)}'
    os.makedirs(d, exist_ok=True)
    fpath = os.path.join(d, f'sim_{sensor_id}.dat')
    with open(fpath, 'wb') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(struct.pack('<i', sensor_id))
        f.write(struct.pack('<100f', *[random.random() for _ in range(100)]))
        fcntl.flock(f, fcntl.LOCK_UN)
    sensor_id += 1
    time.sleep(0.1)
EOF

    cat << 'EOF' > /app/services/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/services/flask_app.py &
python3 /app/services/sensor_simulator.py &
EOF
    chmod +x /app/services/start_services.sh

    cat << 'EOF' > /app/scripts/generate_batch.py
import sys
import os
import struct
import random

if len(sys.argv) != 2:
    sys.exit(1)
n = int(sys.argv[1])
for sensor_id in range(n):
    d = f'/app/raw_data/station_{random.randint(1,10)}/day_{random.randint(1,10)}'
    os.makedirs(d, exist_ok=True)
    fpath = os.path.join(d, f'batch_{sensor_id}.dat')
    with open(fpath, 'wb') as f:
        f.write(struct.pack('<i', sensor_id))
        f.write(struct.pack('<100f', *[random.random() for _ in range(100)]))
EOF

    cat << 'EOF' > /app/verify_performance.sh
#!/bin/bash
# Stops simulator
pkill -f sensor_simulator.py
rm -rf /app/raw_data/* /app/organized_data/*
redis-cli FLUSHALL
mkdir -p /app/organized_data

# Generate exactly 50,000 files across multiple dirs
python3 /app/scripts/generate_batch.py 50000

START_TIME=$(date +%s.%N)
/home/user/organizer
END_TIME=$(date +%s.%N)

DURATION=$(echo "$END_TIME - $START_TIME" | bc)

# Verification checks
EXPECTED_COUNT=50000
REDIS_COUNT=$(redis-cli SCARD processed_sensors)
FILE_COUNT=$(find /app/organized_data/ -name "clean_*.dat" | wc -l)
CSV_COUNT=$(wc -l < /app/organized_data/summary.csv)

if [ "$REDIS_COUNT" -ne "$EXPECTED_COUNT" ] || [ "$FILE_COUNT" -ne "$EXPECTED_COUNT" ] || [ "$CSV_COUNT" -ne "$EXPECTED_COUNT" ]; then
    echo "State validation failed: Redis=$REDIS_COUNT, Files=$FILE_COUNT, CSV=$CSV_COUNT (Expected $EXPECTED_COUNT)"
    exit 1
fi

echo "execution_time: $DURATION"
if (( $(echo "$DURATION <= 3.0" | bc -l) )); then
    echo "PASS"
    exit 0
else
    echo "FAIL"
    exit 1
fi
EOF
    chmod +x /app/verify_performance.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
