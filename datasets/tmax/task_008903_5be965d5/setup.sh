#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc g++
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/targets
cd /home/user/targets

cat << 'EOF' > safe_bin.c
int main() { return 0; }
EOF

cat << 'EOF' > suid_bin.c
const char* s = "/etc/shadow";
int main() { return 0; }
EOF

cat << 'EOF' > fake_bin.c
char s[] = "/etc/shadow";
int main() { return 0; }
EOF

gcc safe_bin.c -o safe_bin
gcc suid_bin.c -o suid_bin
gcc fake_bin.c -o fake_bin

rm *.c

chmod -R 777 /home/user
chmod 4755 /home/user/targets/suid_bin
chmod 4755 /home/user/targets/fake_bin
