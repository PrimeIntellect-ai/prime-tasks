#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Create python script to generate data
    # Note: We use string concatenation for the template placeholder to avoid Apptainer build variable syntax errors.
    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user', exist_ok=True)

with open('/home/user/report_template.md', 'w') as f:
    f.write("# System Latency and Status Report\n\n" + "{" + "{content}" + "}")

deterministic_entries = [
    "[2023-10-01 10:00:00] [INFO] [UID:U1001] Action LOGIN resulted in code 200. Latency: 1500ms. Msg: Success\n",
    "[2023-10-01 10:00:01] [INFO] [UID:U1002] Action QUERY resulted in code 200. Latency: 1450ms. Msg: Success\n",
    "[2023-10-01 10:00:02] [INFO] [UID:U1003] Action UPLOAD resulted in code 200. Latency: 1400ms. Msg: Success\n",

    "[2023-10-01 10:01:00] [ERROR] [UID:U2001] Action LOGIN resulted in code 500. Latency: 5000ms. Msg: DB timeout\n",
    "[2023-10-01 10:01:01] [ERROR] [UID:U2002] Action QUERY resulted in code 500. Latency: 4999ms. Msg: DB timeout\n",
    "[2023-10-01 10:01:02] [ERROR] [UID:U2003] Action UPLOAD resulted in code 500. Latency: 4500ms. Msg: DB timeout\n",

    "[2023-10-01 10:02:00] [WARN] [UID:U3001] Action DOWNLOAD resulted in code 404. Latency: 800ms. Msg: Not found\n",
    "[2023-10-01 10:02:01] [WARN] [UID:U3002] Action DOWNLOAD resulted in code 404. Latency: 750ms. Msg: Not found\n"
]

with open('/home/user/raw_logs.txt', 'w') as f:
    for _ in range(100):
        f.write("Junk line logging system initialized...\n")

    random.seed(42)
    for _ in range(5000):
        code = random.choice([200, 404, 500])
        latency = random.randint(10, 500)
        action = random.choice(["LOGIN", "QUERY", "UPLOAD", "DOWNLOAD"])
        uid = f"R{random.randint(100, 999)}"
        level = "INFO" if code == 200 else ("WARN" if code == 404 else "ERROR")
        f.write(f"[2023-10-01 12:00:00] [{level}] [UID:{uid}] Action {action} resulted in code {code}. Latency: {latency}ms. Msg: Random log\n")

        if random.random() < 0.1:
            f.write("Some random trace output: memory address 0x00FF\n")

    for entry in deterministic_entries:
        f.write(entry)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
