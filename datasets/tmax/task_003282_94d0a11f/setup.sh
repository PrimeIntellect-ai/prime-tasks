#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc rustc cargo logrotate
pip3 install pytest

mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

cat << 'EOF' > /tmp/setup.py
import os

c_code = """
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 0;
    char buffer[4096];
    size_t len = fread(buffer, 1, sizeof(buffer)-1, f);
    buffer[len] = '\\0';
    fclose(f);

    char *mac = strstr(buffer, "mac=");
    if (mac) {
        int colons = 0;
        for (int i = 4; mac[i] != '\\0' && mac[i] != ' ' && mac[i] != ',' && mac[i] != '\\n'; i++) {
            if (mac[i] == ':') colons++;
        }
        if (colons < 5) abort();
    }

    char *net = strstr(buffer, "net=10.");
    if (net) {
        char *slash = strchr(net, '/');
        if (slash) {
            int cidr = atoi(slash + 1);
            if (cidr < 16) abort();
        }
    }

    return 0;
}
"""

with open("/tmp/validator.c", "w") as f:
    f.write(c_code)

os.system("gcc -O2 /tmp/validator.c -o /app/deploy-validator")
os.system("strip /app/deploy-validator")

for i in range(50):
    with open(f"/app/corpus/clean/file_{i}.txt", "w") as f:
        f.write(f"-netdev user,id=net0,net=10.0.2.0/24 -device e1000,netdev=net0,mac=52:54:00:12:34:{i:02x}\n")

for i in range(25):
    with open(f"/app/corpus/evil/file_mac_{i}.txt", "w") as f:
        f.write(f"-netdev user,id=net0,net=10.0.2.0/24 -device e1000,netdev=net0,mac=52:54:00:12:{i:02x}\n")

for i in range(25):
    with open(f"/app/corpus/evil/file_net_{i}.txt", "w") as f:
        f.write(f"-netdev user,id=net0,net=10.0.0.0/8 -device e1000,netdev=net0,mac=52:54:00:12:34:{i:02x}\n")
EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
mkdir -p /home/user/filter_src
chmod -R 777 /home/user
