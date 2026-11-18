#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/sensor_net/output
    cd /home/user/sensor_net

    cat << 'EOF' > sensor1.py
import socket
import time
import json
import random

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
while True:
    data = {"sensor": 1, "value": random.uniform(20.0, 30.0)}
    s.sendto(json.dumps(data).encode('utf-8'), ('127.0.0.1', 9001))
    time.sleep(0.5)
EOF

    cat << 'EOF' > sensor2.py
import socket
import time
import json
import random

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
counter = 0
while True:
    counter += 1
    # Inject an outlier every 4th message
    if counter % 4 == 0:
        val = 1e12 # Massive outlier
    else:
        val = random.uniform(20.0, 30.0)
    data = {"sensor": 2, "value": val}
    s.sendto(json.dumps(data).encode('utf-8'), ('127.0.0.1', 9001))
    time.sleep(0.4)
EOF

    cat << 'EOF' > sensor3.py
import socket
import time
import json
import random

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
counter = 0
while True:
    counter += 1
    data = {"sensor": 3, "value": random.uniform(20.0, 30.0)}
    payload = json.dumps(data)
    # Inject bad encoding every 3rd message
    if counter % 3 == 0:
        encoded = payload.encode('utf-16le')
    else:
        encoded = payload.encode('utf-8')
    s.sendto(encoded, ('127.0.0.1', 9001))
    time.sleep(0.6)
EOF

    cat << 'EOF' > aggregator.py
import socket
import json
import math
import time

def process_data():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(('127.0.0.1', 9001))
    s.settimeout(1.0)

    window = []

    with open('/home/user/sensor_net/output/metrics.log', 'a') as f:
        while True:
            try:
                data, addr = s.recvfrom(4096)

                # BUG 1: Only attempts utf-8, will crash on sensor 3's utf-16le
                text = data.decode('utf-8')
                record = json.loads(text)

                # BUG 2: No filtering of anomalies
                val = record['value']
                window.append(val)

                if len(window) > 10:
                    window.pop(0)

                if len(window) >= 5:
                    # Naive variance calculation, susceptible to catastrophic cancellation
                    # when an outlier like 1e12 is present
                    n = len(window)
                    sum_x = sum(window)
                    sum_x2 = sum(x**2 for x in window)

                    variance = (sum_x2 - (sum_x**2)/n) / n

                    # Crash happens here when variance becomes slightly negative due to float precision
                    stddev = math.sqrt(variance)

                    f.write(f"Count: {n}, StdDev: {stddev:.4f}\n")
                    f.flush()

            except socket.timeout:
                continue
            except KeyboardInterrupt:
                break

if __name__ == '__main__':
    process_data()
EOF

    cat << 'EOF' > start.sh
#!/bin/bash
python3 sensor1.py &
P1=$!
python3 sensor2.py &
P2=$!
python3 sensor3.py &
P3=$!

python3 aggregator.py
kill $P1 $P2 $P3
EOF
    chmod +x start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
