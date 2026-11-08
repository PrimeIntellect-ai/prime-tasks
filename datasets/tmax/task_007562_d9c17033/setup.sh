#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/model_weights.json
{
  "W1": 0.4,
  "W2": -0.8,
  "W3": 1.2,
  "b": -0.1
}
EOF

    python3 -c "
import csv
import random

random.seed(42)
with open('/home/user/data/raw_metrics.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'f1', 'f2', 'f3', 'f4', 'f5'])

    for i in range(1, 1001):
        f1 = random.uniform(0, 1)
        f2 = random.uniform(0, 1)
        f3 = random.uniform(0, 1)

        # Determine score for correlation logic
        score = (f1 * 0.4) + (f2 * -0.8) + (f3 * 1.2) - 0.1

        # Inject correlation
        if score > 0.5:
            # Anomaly: strong negative correlation between f4 and f5
            f4 = random.uniform(0, 10)
            f5 = -2.0 * f4 + random.uniform(0, 2)
        else:
            # Normal: positive correlation
            f4 = random.uniform(0, 10)
            f5 = 1.5 * f4 + random.uniform(0, 2)

        writer.writerow([i, f1, f2, f3, f4, f5])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
