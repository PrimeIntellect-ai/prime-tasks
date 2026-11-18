#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd tar xz-utils
    pip3 install pytest flask

    mkdir -p /home/user/incoming /home/user/processed /app

    # Create generator script
    cat << 'EOF' > /app/log_generator.py
import time
while True:
    time.sleep(10)
EOF

    # Create dashboard script
    cat << 'EOF' > /app/dashboard.py
from flask import Flask
app = Flask(__name__)
@app.route('/')
def index():
    return "Dashboard"
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    # Generate spool.tar
    cat << 'EOF' > /app/generate_spool.py
import tarfile
import os

os.makedirs("/home/user/incoming", exist_ok=True)
os.makedirs("/home/user/processed", exist_ok=True)

log_content = []
for i in range(5000):
    log_content.append("=== RECORD START ===\n")
    log_content.append("Timestamp: 2023-10-24T10:00:00Z\n")
    log_content.append("Severity: CRITICAL\n")
    log_content.append("Message: \n")
    log_content.append("  Database connection timeout.\n")
    log_content.append("  Retrying in 5 seconds...\n")
    log_content.append("  [Traceback data...]\n")
    log_content.append(f"Bloat-Padding: {'A'*10000}\n")
    log_content.append("=== RECORD END ===\n")

with open("/tmp/log.txt", "w") as f:
    f.writelines(log_content)

with tarfile.open("/home/user/incoming/spool.tar", "w") as tar:
    tar.add("/tmp/log.txt", arcname="log.txt")
EOF

    python3 /app/generate_spool.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
