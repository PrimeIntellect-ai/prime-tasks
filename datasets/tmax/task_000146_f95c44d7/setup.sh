#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import random

random.seed(123)
with open("/home/user/data.csv", "w") as f:
    f.write("id,value\n")
    for i in range(1, 500001):
        r = random.random()
        if r < 0.04:
            f.write(f"{i},NaN\n")
        elif r < 0.08:
            f.write(f"{i},\n")
        else:
            # Generate values spanning the 64-bit signed int range
            val = random.randint(-9223372036854775000, 9223372036854775000)
            f.write(f"{i},{val}\n")

    # Inject specific max and min to guarantee strict exact values
    # These values are large enough that casting to double would lose precision
    f.write("500001,9223372036854775806\n")
    f.write("500002,-9223372036854775807\n")
EOF

    python3 /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
