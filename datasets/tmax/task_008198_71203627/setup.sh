#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/remote_servers/server_1
    mkdir -p /home/user/remote_servers/server_2
    mkdir -p /home/user/remote_servers/server_3
    mkdir -p /home/user/analysis/raw_logs/

    cat << 'EOF' > /home/user/setup_logs.py
import random
from datetime import datetime, timedelta

random.seed(42)

def generate_logs(filename, error_profile):
    base_time = datetime(2023, 10, 10, 0, 0, 0)
    with open(filename, 'w') as f:
        for hour in range(24):
            # Normal traffic (status 200)
            num_normal = random.randint(50, 100)
            for _ in range(num_normal):
                minute = random.randint(0, 59)
                sec = random.randint(0, 59)
                t = base_time + timedelta(hours=hour, minutes=minute, seconds=sec)
                f.write(f'192.168.1.1 - - [{t.strftime("%d/%b/%Y:%H:%M:%S +0000")}] "GET /api HTTP/1.1" 200 512\n')

            # Error traffic (status 502)
            num_errors = error_profile[hour]
            for _ in range(num_errors):
                minute = random.randint(0, 59)
                sec = random.randint(0, 59)
                t = base_time + timedelta(hours=hour, minutes=minute, seconds=sec)
                f.write(f'192.168.1.2 - - [{t.strftime("%d/%b/%Y:%H:%M:%S +0000")}] "GET /api HTTP/1.1" 502 512\n')

# Profiles: 1 and 3 are very similar. 2 is different.
profile_1 = [5 if h in [8, 14, 20] else 1 for h in range(24)]
profile_3 = [6 if h in [8, 14, 20] else 1 for h in range(24)] # Very close to 1
profile_2 = [15 if h in [2, 10, 18] else 2 for h in range(24)] # Different

generate_logs('/home/user/remote_servers/server_1/access.log', profile_1)
generate_logs('/home/user/remote_servers/server_2/access.log', profile_2)
generate_logs('/home/user/remote_servers/server_3/access.log', profile_3)
EOF

    python3 /home/user/setup_logs.py
    rm /home/user/setup_logs.py

    chmod -R 777 /home/user
