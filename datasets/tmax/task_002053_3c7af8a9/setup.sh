#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget make gcc jq coreutils
    pip3 install pytest xxhash

    mkdir -p /app/vendored
    cd /app/vendored
    wget https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.1.tar.gz
    tar -xzf v0.8.1.tar.gz
    rm v0.8.1.tar.gz

    # Introduce the perturbation in the Makefile
    sed -i 's/DISPATCH ?= 0/DISPATCH ?= 1/g' /app/vendored/xxHash-0.8.1/Makefile

    # Create the oracle script
    cat << 'EOF' > /app/oracle_etl
#!/usr/bin/env python3
import sys
import json
import xxhash

if len(sys.argv) != 2:
    sys.exit(1)

input_file = sys.argv[1]

with open(input_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            if 'user_id' not in data or 'amount' not in data:
                continue
            user_id = str(data['user_id'])
            amount = float(data['amount'])
            if amount < 0.0:
                amount = 0.0
            elif amount > 1000.0:
                amount = 1000.0

            h = xxhash.xxh32(user_id.encode('utf-8')).hexdigest()
            print(f"{h},{amount:.2f}")
        except Exception:
            pass
EOF
    chmod +x /app/oracle_etl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
