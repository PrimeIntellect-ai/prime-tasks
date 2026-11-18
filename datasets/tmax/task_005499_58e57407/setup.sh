#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

python3 -c '
import os
import hmac
import hashlib

c_code = """
#include <stdio.h>
int main() {
    // Hidden secret key
    char secret[] = "N3tw0rkS3cur1ty!!";
    printf("Auth daemon running.\\n");
    return 0;
}
"""
with open("/home/user/auth_daemon.c", "w") as f:
    f.write(c_code)

os.system("gcc /home/user/auth_daemon.c -o /home/user/auth_daemon")
os.remove("/home/user/auth_daemon.c")

secret = b"N3tw0rkS3cur1ty!!"
lines = []
expected_valid_lines = []
for i in range(1600000000, 1600000020):
    ts = str(i).encode()
    if i % 3 != 0:  # Valid tokens
        token = hmac.new(secret, ts, hashlib.sha256).hexdigest()
        line = f"{i},{token}\n"
        lines.append(line)
        expected_valid_lines.append(line)
    else:  # Invalid tokens
        token = hmac.new(secret, ts + b"bad", hashlib.sha256).hexdigest()
        line = f"{i},{token}\n"
        lines.append(line)

with open("/home/user/intercepted.log", "w") as f:
    f.writelines(lines)

with open("/home/user/.expected_valid_traffic.log", "w") as f:
    f.writelines(expected_valid_lines)
'

chmod -R 777 /home/user
