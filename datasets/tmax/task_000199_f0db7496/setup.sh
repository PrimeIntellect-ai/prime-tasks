#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    echo "Take a JSON array of integers. For each integer x, compute x squared minus three times x. If the result is strictly less than zero, multiply it by negative one to make it positive. Serialize the output as a JSON dictionary where the keys are the string indices of the original array, and the values are the base64 encoded strings of the unsigned 32-bit big-endian byte representation of the computed numbers. Print this JSON object to standard output." | espeak -w /app/spec_memo.wav

    mkdir -p /verify
    cat << 'EOF' > /verify/reference.py
import sys
import json
import base64

def process():
    input_data = sys.stdin.read()
    if not input_data.strip():
        return
    arr = json.loads(input_data)
    out = {}
    for i, x in enumerate(arr):
        val = (x ** 2) - (3 * x)
        if val < 0:
            val = -val
        # 32-bit big-endian unsigned
        b = val.to_bytes(4, byteorder='big', signed=False)
        b64 = base64.b64encode(b).decode('ascii')
        out[str(i)] = b64
    print(json.dumps(out, separators=(',', ':')))

if __name__ == '__main__':
    process()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
