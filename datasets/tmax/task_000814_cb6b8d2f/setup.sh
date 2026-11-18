#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip binutils
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > /home/user/calc_stddev.py
import math
import sys
import json

def stddev(data):
    n = len(data)
    if n == 0:
        return 0.0
    sum_x = sum(data)
    sum_x2 = sum(x**2 for x in data)
    # Naive variance calculation, prone to catastrophic cancellation
    variance = (sum_x2 / n) - ((sum_x / n)**2)
    return math.sqrt(variance)

if __name__ == '__main__':
    try:
        payload = json.loads(sys.argv[1])
        print(stddev(payload['data']))
    except Exception as e:
        print(f"Error: {type(e).__name__} - {e}")
        sys.exit(1)
EOF
chmod +x /home/user/calc_stddev.py

cat << 'EOF' > /home/user/api.log
2023-10-24T09:12:01Z INFO Request received ReqID=req-801 Status=Processing
2023-10-24T09:13:14Z INFO Request received ReqID=req-802 Status=Processing
2023-10-24T09:15:22Z INFO Request received ReqID=req-803 Status=Processing
2023-10-24T09:18:45Z INFO Request received ReqID=req-804 Status=Processing
2023-10-24T09:20:05Z INFO Request received ReqID=req-805 Status=Processing
EOF

python3 -c '
import struct
import random

payloads = [
    b"{\"req_id\": \"req-801\", \"data\": [1.5, 2.5, 3.5]}",
    b"{\"req_id\": \"req-802\", \"data\": [10.0, 10.0, 10.0]}",
    b"{\"req_id\": \"req-803\", \"data\": [1e9, 1e9+1, 1e9+2]}", 
    b"{\"req_id\": \"req-804\", \"data\": [100.1, 102.3, 99.8]}",
    b"{\"req_id\": \"req-805\", \"data\": [0.0, 0.0, 0.1]}"
]

with open("/home/user/worker_mem.dump", "wb") as f:
    for p in payloads:
        # Write some random garbage bytes
        f.write(bytes([random.randint(0, 255) for _ in range(128)]))
        # Write the payload
        f.write(p)
        # Write more garbage
        f.write(bytes([random.randint(0, 255) for _ in range(128)]))
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
