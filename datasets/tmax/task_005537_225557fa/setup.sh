#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/encode.py
import base64
import sys
import ast

def encode_vlq(n):
    if n == 0:
        return [0]
    chunks = []
    while n > 0:
        chunks.append(n & 0x7F)
        n >>= 7
    chunks.reverse()
    for i in range(len(chunks) - 1):
        chunks[i] |= 0x80
    return chunks

def custom_encode(nums):
    if not nums: return ""

    # Delta
    deltas = [nums[0]]
    for i in range(1, len(nums)):
        deltas.append(nums[i] - nums[i-1])

    # ZigZag with a deliberate bug for delta == -5
    zigzags = []
    for d in deltas:
        if d == -5:
            zigzags.append(10) # Bug: should be 9
        elif d >= 0:
            zigzags.append(2 * d)
        else:
            zigzags.append(-2 * d - 1)

    # VLQ
    bytes_out = []
    for z in zigzags:
        bytes_out.extend(encode_vlq(z))

    return base64.b64encode(bytes(bytes_out)).decode('utf-8')

if __name__ == "__main__":
    if len(sys.argv) > 1:
        nums = ast.literal_eval(sys.argv[1])
        print(custom_encode(nums))
EOF
    chmod +x /home/user/encode.py

    chmod -R 777 /home/user
