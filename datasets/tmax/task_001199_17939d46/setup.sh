#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect netcat
pip3 install pytest

mkdir -p /home/user/pipeline

cat << 'EOF' > /home/user/pipeline/config.ini
[server]
host = 127.0.0.1
port = 9999
EOF

cat << 'EOF' > /home/user/pipeline/aggregator.py
import sys
import socket
import configparser
print("Enter PIN: ", end="", flush=True)
pin = sys.stdin.readline().strip()
if pin != "7788":
    print("Invalid PIN")
    sys.exit(1)
config = configparser.ConfigParser()
config.read('/home/user/pipeline/config.ini')
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind((config['server']['host'], int(config['server']['port'])))
s.listen(1)
with open("/home/user/pipeline/agg_out.log", "w") as f:
    f.write("STARTED\n")
    f.flush()
conn, addr = s.accept()
data = conn.recv(1024)
if b"PING" in data:
    with open("/home/user/pipeline/agg_out.log", "a") as f:
        f.write("PONG\n")
EOF

mkdir -p /opt/oracle
cat << 'EOF' > /opt/oracle/planner_oracle.py
import sys
import re
pattern = re.compile(r"^DATA node=([a-zA-Z0-9]+) cpu=(\d+) mem=(\d+) disk=(\d+)$")
for line in sys.stdin:
    line = line.strip('\n')
    match = pattern.match(line)
    if match:
        node, cpu, mem, disk = match.groups()
        score = (int(cpu) * 2) + (int(mem) // 10) + (int(disk) * 5)
        if score > 500:
            print(f"ALERT {node} {score}")
        else:
            print(f"OK {node} {score}")
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
