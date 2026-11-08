#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "Hey, it's the senior admin. We need to lock down SSH. Write a python script that reads the username and IP. If the username is exactly root, deny it. If the username is shorter than five characters, deny it. If the IP is not a valid IPv4 address, deny it. Finally, if the IPv4 address ends in dot two five five, deny it as it is a broadcast address. Otherwise, allow it. That's all."

    cat << 'EOF' > /opt/oracle.py
import sys

def check():
    line = sys.stdin.read().strip()
    try:
        user, ip = line.split(' ')
    except ValueError:
        print("DENY")
        return

    if user == "root":
        print("DENY")
        return

    if len(user) < 5:
        print("DENY")
        return

    parts = ip.split('.')
    if len(parts) != 4:
        print("DENY")
        return

    for p in parts:
        if not p.isdigit() or not 0 <= int(p) <= 255:
            print("DENY")
            return

    if parts[-1] == '255':
        print("DENY")
        return

    print("ALLOW")

if __name__ == '__main__':
    check()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
