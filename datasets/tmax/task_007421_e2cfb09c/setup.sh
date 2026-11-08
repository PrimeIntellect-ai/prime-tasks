#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/services.json
{
    "db_mock": {
        "command": "python3 /home/user/db_mock.py",
        "depends_on_port": null
    },
    "backend": {
        "command": "python3 /home/user/backend.py",
        "depends_on_port": 5432
    }
}
EOF

    cat << 'EOF' > /home/user/db_mock.py
import time
import socket
import sys

print("DB Mock starting... simulating initialization delay.")
time.sleep(3)
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(('127.0.0.1', 5432))
s.listen(1)
print("DB Mock listening on 5432")
while True:
    time.sleep(10)
EOF

    cat << 'EOF' > /home/user/supervisor.py
import json
import subprocess
import time

def main():
    with open('/home/user/services.json') as f:
        services = json.load(f)

    processes = []
    for name, config in services.items():
        print(f"Launching {name}...")
        cmd = config['command'].split()
        p = subprocess.Popen(cmd)
        processes.append(p)

    try:
        for p in processes:
            p.wait()
    except KeyboardInterrupt:
        for p in processes:
            p.terminate()

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
