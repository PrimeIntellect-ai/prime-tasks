#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sensor_service

    cat << 'EOF' > /home/user/sensor_service/build_data.sh
#!/bin/bash
# Fails because data directory doesn't exist
cd /home/user/sensor_service/data
python3 -c "
import random
random.seed(42)
with open('../sensor_data.csv', 'w') as f:
    for _ in range(100000):
        f.write(f'{1000000 + random.uniform(-1, 1)}\n')
"
EOF
    chmod +x /home/user/sensor_service/build_data.sh

    cat << 'EOF' > /home/user/sensor_service/processor.py
import sys

def process_data():
    data_history = [] # Memory leak: keeps growing forever
    sum_x = 0.0
    sum_x2 = 0.0
    count = 0

    with open('/home/user/sensor_service/sensor_data.csv', 'r') as f:
        for line in f:
            val = float(line.strip())
            data_history.append(val) # Leak

            sum_x += val
            sum_x2 += val * val
            count += 1

    # Catastrophic cancellation in naive variance
    mean = sum_x / count
    variance = (sum_x2 / count) - (mean * mean)

    with open('/home/user/sensor_service/final_metrics.txt', 'w') as f:
        f.write(f"Variance: {variance:.4f}\n")

if __name__ == '__main__':
    process_data()
EOF

    chmod -R 777 /home/user
