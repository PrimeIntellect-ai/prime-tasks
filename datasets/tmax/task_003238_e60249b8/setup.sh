#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest

    # Download and extract pyzstd-0.15.9
    mkdir -p /app
    cd /app
    pip3 download --no-binary :all: pyzstd==0.15.9
    tar -xzf pyzstd-0.15.9.tar.gz
    rm pyzstd-0.15.9.tar.gz

    # Inject the bad compiler flag into setup.py
    sed -i "1i import os; os.environ['CFLAGS'] = '-fbreak-my-build-123 ' + os.environ.get('CFLAGS', '')" /app/pyzstd-0.15.9/setup.py

    # Create the user
    useradd -m -s /bin/bash user || true

    # Generate the log files
    cat << 'EOF' > /tmp/generate_logs.py
import os
import random
import time
from datetime import datetime

os.makedirs('/home/user/raw_logs', exist_ok=True)

encodings = ['utf-8', 'utf-16le', 'iso-8859-1']
start_2021 = time.mktime(datetime(2021, 1, 1).timetuple())
end_2021 = time.mktime(datetime(2021, 12, 31).timetuple())
start_2022 = time.mktime(datetime(2022, 1, 1).timetuple())

random.seed(42)

for i in range(100):
    is_2021 = random.choice([True, False])
    mtime = random.uniform(start_2021, end_2021) if is_2021 else random.uniform(start_2022, start_2022 + 1000000)
    encoding = random.choice(encodings)

    lines = []
    for _ in range(500):
        if random.random() < 0.4:
            lines.append("[DEBUG] Context payload memory addr 0x" + f"{random.randint(0, 100000):08x}\n")
        else:
            lines.append(f"[INFO] Regular operation tick {random.randint(0, 10000)}\n")

    content = "".join(lines).encode(encoding)
    filepath = f"/home/user/raw_logs/system_{i}.log"

    with open(filepath, 'wb') as f:
        f.write(content)

    os.utime(filepath, (mtime, mtime))
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user
    chmod -R 777 /app
