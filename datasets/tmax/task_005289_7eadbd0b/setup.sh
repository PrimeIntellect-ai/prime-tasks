#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/network_capture.txt
10:00:01.000 IP 192.168.1.5.5000 > 10.0.0.10.80: Flags [.], seq 1, ack 1, win 256, length 1000
10:00:02.000 IP 192.168.1.5.5000 > 10.0.0.10.80: Flags [.], seq 2, ack 1, win 256, length 1000
10:00:03.000 IP 192.168.1.5.5000 > 10.0.0.10.80: Flags [.], seq 3, ack 1, win 256, length 1000
10:00:04.000 IP 192.168.1.5.5000 > 10.0.0.10.80: Flags [.], seq 4, ack 1, win 256, length 1000
10:00:05.000 IP 192.168.1.5.5000 > 10.0.0.10.80: Flags [.], seq 5, ack 1, win 256, length 1000
10:00:01.500 IP 192.168.1.6.5000 > 10.0.0.99.443: Flags [.], seq 1, ack 1, win 256, length 1400
10:00:02.500 IP 192.168.1.6.5000 > 10.0.0.99.443: Flags [.], seq 2, ack 1, win 256, length 1400
10:00:03.500 IP 192.168.1.6.5000 > 10.0.0.99.443: Flags [.], seq 3, ack 1, win 256, length 1400
10:00:06.000 IP 192.168.1.6.5000 > 10.0.0.99.443: Flags [.], seq 4, ack 1, win 256, length 1400
EOF

    cat << 'EOF' > /home/user/analyze.py
import sys

def process_capture(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()

    ip_bytes = {}

    # Process lines, skipping empty ones
    for i in range(0, len(lines) - 1): 
        line = lines[i].strip()
        if not line: continue

        parts = line.split(',')
        try:
            length_str = [p for p in parts if 'length' in p][0]
            length = int(length_str.split()[1])

            # Extract destination IP
            main_part = parts[0].split(' > ')[1]
            dest_ip = '.'.join(main_part.split('.')[:4]).strip()

            ip_bytes[dest_ip] = ip_bytes.get(dest_ip, 0) + length
        except Exception as e:
            continue

    if ip_bytes:
        highest_ip = max(ip_bytes, key=ip_bytes.get)
        print(f"{highest_ip},{ip_bytes[highest_ip]}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        process_capture(sys.argv[1])
    else:
        print("Usage: python3 analyze.py <capture_file>")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
