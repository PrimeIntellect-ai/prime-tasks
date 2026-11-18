#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/account_system/profiles

    cat << 'EOF' > /home/user/account_system/db_init.py
#!/usr/bin/env python3
import time
import os

print("Starting db_init...")
time.sleep(2)
with open("/home/user/account_system/db.lock", "w") as f:
    f.write("READY")
print("db_init finished.")
EOF
    chmod +x /home/user/account_system/db_init.py

    cat << 'EOF' > /home/user/account_system/profile_gen.py
#!/usr/bin/env python3
import os
import sys

print("Starting profile_gen...")
if not os.path.exists("/home/user/account_system/db.lock"):
    print("Error: db.lock not found! Dependency failed.")
    sys.exit(1)

fail_state_file = "/home/user/account_system/fail_state.tmp"
if not os.path.exists(fail_state_file):
    # Simulate flaky failure on first run
    with open(fail_state_file, "w") as f:
        f.write("FAILED_ONCE")
    print("Error: Simulated flaky network failure.")
    sys.exit(2)

os.makedirs("/home/user/account_system/profiles/groupA", exist_ok=True)
with open("/home/user/account_system/profiles/groupA/user1.json", "w") as f:
    f.write('{"user": "user1"}')
with open("/home/user/account_system/profiles/user2.json", "w") as f:
    f.write('{"user": "user2"}')
print("profile_gen finished successfully.")
EOF
    chmod +x /home/user/account_system/profile_gen.py

    cat << 'EOF' > /home/user/account_system/supervisor.py
#!/usr/bin/env python3
import subprocess

print("Supervisor starting...")
p1 = subprocess.Popen(["python3", "/home/user/account_system/db_init.py"])
p2 = subprocess.Popen(["python3", "/home/user/account_system/profile_gen.py"])

p1.wait()
p2.wait()
print("Supervisor exiting.")
EOF

    chmod -R 777 /home/user
