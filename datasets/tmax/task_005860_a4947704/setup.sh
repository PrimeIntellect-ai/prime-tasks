#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/generate_logs.py
import random
from datetime import datetime, timedelta

random.seed(42)

users = ["U" + str(i).zfill(3) for i in range(1, 21)]
actions = ["purchase", "login", "view", "PURCHASE", "View", "Purchase"]
ips = ["192.168.1.10", "10.0.0.5", "172.16.0.8", "192.168.1.11", "8.8.8.8"]

base_time = datetime(2023, 10, 1, 12, 0, 0)

with open("/home/user/etl_dump.log", "w") as f:
    txn_counter = 1000
    for _ in range(500):
        user = random.choice(users)
        action = random.choice(actions)
        amount = random.randint(10, 100) if action.lower() == "purchase" else 0
        ip = random.choice(ips)

        payload_text = random.choice(["Retry attempt.", "Initial processing.", "Failed step."])
        raw_payload = payload_text + ' DATA={action: "' + action + '", amount: "' + str(amount) + '", ip: "' + ip + '"}'

        # Write initial record
        timestamp = (base_time + timedelta(seconds=random.randint(0, 3600))).isoformat() + "Z"
        f.write(timestamp + " | TXN-" + str(txn_counter) + " | " + user + " | " + raw_payload + "\n")
        txn_counter += 1

        # Write duplicates
        if random.random() < 0.4:
            for _ in range(random.randint(1, 3)):
                timestamp = (base_time + timedelta(seconds=random.randint(3600, 7200))).isoformat() + "Z"
                f.write(timestamp + " | TXN-" + str(txn_counter) + " | " + user + " | " + raw_payload + "\n")
                txn_counter += 1
EOF

python3 /home/user/generate_logs.py
rm /home/user/generate_logs.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
