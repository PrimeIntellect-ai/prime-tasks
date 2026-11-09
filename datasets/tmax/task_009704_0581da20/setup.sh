#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import random

random.seed(42)
with open("/home/user/raw_vectors.csv", "w") as f:
    record_id = 1000
    for _ in range(5000):
        # Generate base coefficients
        coeffs = [random.randint(0, 100) for _ in range(10)]

        # Write original
        record_id += 1
        f.write(f"{record_id}," + ",".join(map(str, coeffs)) + "\n")

        # Generate 0 to 3 duplicates (same coeffs, different record_id)
        # They will evaluate to the same hash
        num_dupes = random.randint(0, 3)
        for _ in range(num_dupes):
            record_id += random.randint(1, 10)
            f.write(f"{record_id}," + ",".join(map(str, coeffs)) + "\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
