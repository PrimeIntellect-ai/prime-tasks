#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc openssh-client
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/.ssh

cat << 'EOF' > /tmp/vuln.c
const char* sig = "AUTH_SIG:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08";
int main() { return 0; }
EOF
gcc /tmp/vuln.c -o /home/user/vulnerable_service.bin
rm /tmp/vuln.c

chmod -R 777 /home/user
