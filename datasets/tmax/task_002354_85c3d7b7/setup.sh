#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/metrics.json
[
  {"id": "srv-1", "cpu": 50.0, "memory": 60.0, "uptime": 10},
  {"id": "srv-2", "cpu": 80.0, "memory": 90.0, "uptime": 5}
]
EOF

    cat << 'EOF' > /home/user/fast_math.c
#include <math.h>

double compute_checksum(double value) {
    return sin(value) + cos(value);
}
EOF

    cat << 'EOF' > /home/user/build.sh
#!/bin/bash
gcc -shared -o fast_math.so -fPIC fast_math.c
EOF
    chmod +x /home/user/build.sh

    cat << 'EOF' > /home/user/aggregate_metrics.py
import json
import base64
import ctypes
import math
import sys
import os

# Load C lib
lib_path = os.path.join(os.path.dirname(__file__), 'fast_math.so')
lib = ctypes.CDLL(lib_path)
lib.compute_checksum.argtypes = [ctypes.c_double]
lib.compute_checksum.restype = ctypes.c_double

def calculate_score(cpu, memory, uptime):
    # Buggy implementation
    score = cpu * 1.5 + memory * 2.0 / math.log(uptime) + 2
    return score

def serialize_result(server_id, score, checksum):
    data = {"server": server_id, "score": score, "checksum": checksum}
    json_str = json.dumps(data)
    # Buggy: b64encode needs bytes, not str
    encoded = base64.b64encode(json_str)
    return encoded.decode('utf-8')

def main():
    with open('/home/user/metrics.json', 'r') as f:
        metrics = json.load(f)

    results = []
    for m in metrics:
        score = calculate_score(m['cpu'], m['memory'], m['uptime'])
        checksum = lib.compute_checksum(score)
        res = serialize_result(m['id'], score, checksum)
        results.append(res)

    with open('/home/user/output.txt', 'w') as f:
        for r in results:
            f.write(r + '\n')

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
