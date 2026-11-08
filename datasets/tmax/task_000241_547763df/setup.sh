#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transaction_generator.py
import os
import time
import json

os.makedirs("/home/user/data", exist_ok=True)
filepath = "/home/user/data/transactions.log"

# Deterministic data generation
data_lines = []
data_lines.append(json.dumps({"id": 0, "amount": "100000000.0"}))
for i in range(1, 10001):
    if i % 500 == 0:
        # Corrupt line
        data_lines.append('{"id": ' + str(i) + ', "amount": 0.01\x00')
    elif i % 700 == 0:
        # Another corrupt line
        data_lines.append('{"id": ' + str(i) + ', "amount": ')
    else:
        # Micro transaction
        data_lines.append(json.dumps({"id": i, "amount": "0.01"}))

with open(filepath, "w") as f:
    for line in data_lines:
        f.write(line + "\n")
    f.flush()
    # Keep the file descriptor open indefinitely
    while True:
        time.sleep(10)
EOF

    cat << 'EOF' > /home/user/aggregator.py
import sys
import json

def aggregate(file_path):
    total = 0.0
    with open(file_path, 'r') as f:
        for line in f:
            data = json.loads(line.strip())
            total += float(data['amount'])
    return total

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python aggregator.py <file>")
        sys.exit(1)

    result = aggregate(sys.argv[1])
    print(f"Total: {result}")
EOF

    # Create a startup script to run the background process and delete the directory
    # This will be sourced every time the container is run or exec'd
    mkdir -p /.singularity.d/env
    cat << 'EOF' > /.singularity.d/env/99-start.sh
#!/bin/sh
if ! pgrep -f transaction_generator.py > /dev/null 2>&1; then
    nohup python3 /home/user/transaction_generator.py >/dev/null 2>&1 &
    sleep 2
    rm -rf /home/user/data/
fi
EOF
    chmod +x /.singularity.d/env/99-start.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
