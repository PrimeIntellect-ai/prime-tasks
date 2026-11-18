#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/logs

    # Create log files
    cat << 'EOF' > /home/user/logs/firewall.log
[2023-10-25T10:00:00Z] INBOUND TCP 192.168.1.5:443 Initial connection established
[2023-10-25T10:00:02Z] OUTBOUND TCP 10.0.0.2:80 Connection dropped
EOF

    cat << 'EOF' > /home/user/logs/auth.log
[2023-10-25T10:00:15Z] Failed password for root from 192.168.1.5
[2023-10-25T10:00:18Z] Accepted publickey for user from 192.168.1.5
EOF

    cat << 'EOF' > /home/user/logs/syslog
[2023-10-25T10:00:20Z] service started
[2023-10-25T10:00:42Z] WARNING: Exec payload detected in /tmp/dropper
EOF

    # Create buggy decoder.py
    cat << 'EOF' > /home/user/decoder.py
import sys

# Encrypted payload
encrypted_payload = [108, 99, 105, 112, 85, 83, 19, 83, 87, 82, 83, 90, 21, 160]

def decode_chunk(data, index, key, result):
    # Bug 1: No base case to terminate recursion

    # Bug 2: Incorrect formula
    val = (data[index] ^ key) + (index % 256)
    result.append(val & 0xFF)

    # Bug 3: Fails to increment index, causing infinite recursion
    return decode_chunk(data, index, key, result)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python decoder.py <key>")
        sys.exit(1)

    key = int(sys.argv[1])
    result = []
    try:
        decode_chunk(encrypted_payload, 0, key, result)
        print("".join([chr(b) for b in result]))
    except RecursionError:
        print("Recursion error! Script failed to terminate.")
    except Exception as e:
        print(f"Error: {e}")
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
