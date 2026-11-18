#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > beacon_parser.py
import sys
import argparse

def parse_payload(payload):
    # Bug 2: Edge-case parsing bug. Fails if payload ends with ',' or has empty segments
    segments = payload.split(',')

    # Process weights for checksum
    weights = []
    padding = []
    for seg in segments:
        if seg.replace('.', '', 1).isdigit():
            weights.append(float(seg))
        elif seg.startswith('PAD'):
            padding.append(seg)
        else:
            # Bug 2 triggers here on empty string from trailing comma
            if seg[0] == 'X': 
                pass

    if not weights:
        return True

    # Bug 1: Floating point precision issue
    # 10 * 0.1 in Python summation often yields 0.9999999999999999
    total_weight = sum(weights)

    # The beacon expects weights to sum to exactly 1.0 if there are 10 elements of 0.1
    expected = len(weights) * 0.1
    if total_weight != expected:
        raise ValueError(f"Checksum precision mismatch: {total_weight} != {expected}")

    return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", required=True)
    args = parser.parse_args()

    try:
        parse_payload(args.payload)
        print("Payload processed successfully.")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
EOF

    cat << 'EOF' > crash_payload.txt
0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,PAD1,PAD2,PAD3,
EOF

    chmod +x beacon_parser.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
