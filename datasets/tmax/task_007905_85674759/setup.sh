#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create metadata JSON file
    cat << 'EOF' > /home/user/server_metadata.json
{
  "S1": "Alpha_Node",
  "S2": "Beta_Node",
  "S3": "Gamma_Node"
}
EOF

    # Create Python script to generate the log file
    cat << 'EOF' > /tmp/generate_logs.py
import random

levels = ["INFO", "DEBUG", "ERROR", "CRITICAL", "WARN"]
servers = ["S1", "S2", "S3", "S4"] # S4 will be UNKNOWN
messages = {
    "INFO": "Process completed normally.",
    "DEBUG": "Variable x is 42.",
    "ERROR": "Connection timeout.",
    "CRITICAL": "Kernel panic.",
    "WARN": "Memory usage high."
}

with open("/home/user/app_logs.txt", "w") as f:
    # Ensure exactly 115 ERROR/CRITICAL to test chunking (50, 50, 15)
    target_errors = 115
    errors_generated = 0
    time_counter = 1000

    while errors_generated < target_errors or time_counter < 1300:
        if errors_generated < target_errors:
            level = random.choice(["ERROR", "CRITICAL"])
            errors_generated += 1
        else:
            level = random.choice(["INFO", "DEBUG", "WARN"])

        f.write("[START_ENTRY]\n")
        f.write(f"Timestamp: 2023-10-01T10:{time_counter % 60:02d}:{time_counter % 60:02d}Z\n")
        f.write(f"Level: {level}\n")
        f.write(f"ServerID: {random.choice(servers)}\n")
        f.write(f"Message: {messages[level]}\n")
        f.write("[END_ENTRY]\n")
        time_counter += 1
EOF

    # Run the script to generate logs and then remove it
    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user
