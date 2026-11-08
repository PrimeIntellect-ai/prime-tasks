#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user

    # Create the log generator script
    cat << 'EOF' > /app/generate_logs.py
import random
import string

def gen_key():
    return "ssh-rsa AAAAB3NzaC1" + "".join(random.choices(string.ascii_letters + string.digits, k=40))

logs = []
secret_keys = []

# Generate 100 target lines
for i in range(100):
    key = gen_key()
    secret_keys.append(key)
    logs.append(f"[2023-10-10 10:{random.randint(10,59)}:{random.randint(10,59)}] | 192.168.1.{random.randint(2,254)}:{random.randint(1024,65535)} | netadmin | KEY_EXCHANGE | REJECTED_SILENTLY | {key}")

# Generate 9900 distractor lines
actions = ["LOGIN", "LOGOUT", "KEY_EXCHANGE", "HEARTBEAT"]
statuses = ["SUCCESS", "REJECTED_EXPLICITLY", "TIMEOUT", "ERROR"]
users = ["root", "sysadmin", "guest", "dbadmin", "netadmin"]

for i in range(9900):
    user = random.choice(users)
    action = random.choice(actions)
    status = random.choice(statuses)

    # Ensure we don't accidentally create a target line
    if user == "netadmin" and action == "KEY_EXCHANGE" and status == "REJECTED_SILENTLY":
        status = "SUCCESS"

    key = gen_key() if random.random() > 0.5 else "NO_KEY"
    logs.append(f"[2023-10-10 10:{random.randint(10,59)}:{random.randint(10,59)}] | 10.0.0.{random.randint(2,254)}:{random.randint(1024,65535)} | {user} | {action} | {status} | {key}")

random.shuffle(logs)

with open('/home/user/connection_logs.txt', 'w') as f:
    for log in logs:
        f.write(log + "\n")

with open('/app/.secret_keys', 'w') as f:
    for key in secret_keys:
        f.write(key + "\n")
EOF

    python3 /app/generate_logs.py

    # Create the oracle binary (simulated as an executable python script)
    cat << 'EOF' > /app/net_oracle
#!/usr/bin/env python3
import sys
import os
import json
import re

def main():
    if len(sys.argv) != 2:
        print(json.dumps({"accuracy": 0.0, "error": "Missing configuration bundle directory argument."}))
        sys.exit(1)

    bundle_dir = sys.argv[1]
    fstab_path = os.path.join(bundle_dir, "fstab_snippet")
    group_path = os.path.join(bundle_dir, "group_snippet")
    keys_path = os.path.join(bundle_dir, "authorized_keys")

    # 1. Check fstab_snippet
    fstab_correct = 0
    if os.path.exists(fstab_path):
        try:
            with open(fstab_path, 'r') as f:
                content = f.read()
                required = ['tmpfs', '/home/user/keys_mnt', 'noexec', 'nosuid', 'nodev']
                if all(req in content for req in required):
                    fstab_correct = 1
        except:
            pass

    # 2. Check group_snippet
    group_correct = 0
    if os.path.exists(group_path):
        try:
            with open(group_path, 'r') as f:
                for line in f:
                    if re.match(r'^ssh_mgrs:x:\d+:netadmin$', line.strip()):
                        group_correct = 1
                        break
        except:
            pass

    # 3. Check authorized_keys (Jaccard Similarity)
    jaccard = 0.0
    expected_keys = set()
    try:
        with open('/app/.secret_keys', 'r') as f:
            for line in f:
                if line.strip():
                    expected_keys.add(line.strip())
    except:
        pass

    provided_keys = set()
    if os.path.exists(keys_path):
        try:
            with open(keys_path, 'r') as f:
                for line in f:
                    if line.strip():
                        provided_keys.add(line.strip())
        except:
            pass

    union_len = len(expected_keys.union(provided_keys))
    if union_len > 0:
        jaccard = len(expected_keys.intersection(provided_keys)) / float(union_len)

    # Calculate final accuracy
    accuracy = (0.2 * fstab_correct) + (0.2 * group_correct) + (0.6 * jaccard)

    print(json.dumps({"accuracy": round(accuracy, 4)}))

if __name__ == "__main__":
    main()
EOF

    chmod +x /app/net_oracle

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
