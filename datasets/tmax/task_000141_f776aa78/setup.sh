#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/log_generator.py
import time
import os
from datetime import datetime
import random
import string

RAW_DIR = "/home/user/raw_logs"
os.makedirs(RAW_DIR, exist_ok=True)

def generate_log():
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = os.path.join(RAW_DIR, f"log_{timestamp}.log")
    done_file = os.path.join(RAW_DIR, f"log_{timestamp}.done")

    with open(log_file, "w") as f:
        for _ in range(2500):
            f.write(''.join(random.choices(string.ascii_letters + string.digits, k=99)) + '\n')

    with open(done_file, "w") as f:
        pass

while True:
    generate_log()
    time.sleep(5)
EOF

cat << 'EOF' > /app/start.sh
#!/bin/bash
if ! pgrep -f log_generator.py > /dev/null; then
    nohup python3 /app/log_generator.py > /dev/null 2>&1 &
fi
EOF
chmod +x /app/start.sh

echo '/app/start.sh' >> $APPTAINER_ENVIRONMENT

useradd -m -s /bin/bash user || true
mkdir -p /home/user/raw_logs
chmod -R 777 /home/user
chmod -R 777 /app
