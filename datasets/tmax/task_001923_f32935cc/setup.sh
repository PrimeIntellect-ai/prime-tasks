#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
pip3 install pytest

mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil

espeak -w /app/intercept_774.wav "The backdoor token format is the word omega, followed by the number seven, a hyphen, and exactly sixteen base sixty four characters."

cat << 'EOF' > /tmp/gen_logs.py
import random
import string
import os

def random_string(length, chars=string.ascii_letters + string.digits + "+/"):
    return ''.join(random.choice(chars) for _ in range(length))

for i in range(100):
    with open(f"/app/corpora/clean/log_{i}.txt", "w") as f:
        f.write("sshd[12345]: Accepted publickey for user from 192.168.1.1 port 22 ssh2\n")
        if random.random() < 0.3:
            f.write(f"sshd[12345]: debug1: channel 0: new [client-session] omega8-{random_string(16)}\n")
        elif random.random() < 0.3:
            f.write(f"sshd[12345]: debug1: channel 0: new [client-session] omega7-{random_string(10)}\n")
        else:
            f.write("sshd[12345]: debug1: channel 0: new [client-session]\n")

for i in range(100):
    with open(f"/app/corpora/evil/log_{i}.txt", "w") as f:
        f.write("sshd[12345]: Accepted publickey for user from 192.168.1.1 port 22 ssh2\n")
        f.write(f"sshd[12345]: debug1: channel 0: new [client-session] omega7-{random_string(16)}\n")
EOF

python3 /tmp/gen_logs.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
