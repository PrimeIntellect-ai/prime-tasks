#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user

# 1. Create the C program
cat << 'EOF' > /home/user/get_key.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    int pin = atoi(argv[1]);
    // 5951 ^ 0xcafe = 0xddc1
    if ((pin ^ 0xcafe) == 0xddc1) {
        printf("Tr0jAnK3y\n");
        return 0;
    }
    return 1;
}
EOF

# Compile and clean
gcc /home/user/get_key.c -o /home/user/get_key
rm /home/user/get_key.c
chmod +x /home/user/get_key

# 2. Generate the encrypted payloads and syslog
python3 -c '
import base64
import random

key = "Tr0jAnK3y"
plaintexts = [
    "Exfil from 192.168.1.5 started",
    "Admin creds sent to 10.0.9.99",
    "C2 connect 172.16.0.4 port 443"
]

def encrypt(text, k):
    return bytes([ord(c) ^ ord(k[i % len(k)]) for i, c in enumerate(text)])

with open("/home/user/syslog", "w") as f:
    for i in range(15):
        f.write(f"INFO systemd[{random.randint(100,999)}]: Starting generic service...\n")

    # Payload 1
    enc1 = base64.b64encode(encrypt(plaintexts[0], key)).decode()
    f.write(f"May 12 10:00:01 host kernel: Malicious Payload: {enc1}\n")

    for i in range(8):
        f.write(f"DEBUG cron[{random.randint(1000,9999)}]: run-parts /etc/cron.hourly\n")

    # Payload 2
    enc2 = base64.b64encode(encrypt(plaintexts[1], key)).decode()
    f.write(f"May 12 10:05:22 host custom_daemon: Malicious Payload: {enc2}\n")

    for i in range(5):
        f.write(f"INFO sshd[{random.randint(1000,9999)}]: Disconnected from user root\n")

    # Payload 3
    enc3 = base64.b64encode(encrypt(plaintexts[2], key)).decode()
    f.write(f"May 12 10:11:45 host kernel: Malicious Payload: {enc3}\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
