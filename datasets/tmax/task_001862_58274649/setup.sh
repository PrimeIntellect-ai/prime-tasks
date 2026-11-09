#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential wget tar ltrace strace gdb binutils
pip3 install pytest

# Download and configure jq-1.6
mkdir -p /app
cd /app
wget https://github.com/jqlang/jq/releases/download/jq-1.6/jq-1.6.tar.gz
tar -xzf jq-1.6.tar.gz
rm jq-1.6.tar.gz
cd jq-1.6
./configure
# Remove math library linkage to create the task perturbation
sed -i 's/^LIBS =.*/LIBS = /' Makefile

# Build token_validator
cat << 'EOF' > /tmp/token_validator.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    long probe_id = atol(argv[1]);
    long token = atol(argv[2]);
    if (token == (probe_id * 1337) % 100000) {
        return 0;
    }
    return 1;
}
EOF
gcc -O2 /tmp/token_validator.c -o /usr/local/bin/token_validator
strip /usr/local/bin/token_validator
rm /tmp/token_validator.c

# Create corpus directories and files
mkdir -p /app/corpus/clean /app/corpus/evil

cat << 'EOF' > /app/corpus/clean/clean1.json
{"probe_id": 10, "token": 13370, "uptime_sec": 3500, "total_sec": 3600}
EOF

cat << 'EOF' > /app/corpus/evil/evil1.json
{"probe_id": 10, "token": 13370, "uptime_sec": 4000, "total_sec": 3600}
EOF

cat << 'EOF' > /app/corpus/evil/evil2.json
{"probe_id": 10, "token": 99999, "uptime_sec": 100, "total_sec": 3600}
EOF

cat << 'EOF' > /app/corpus/evil/evil3.json
{"probe_id": 10, "token": 13370, "uptime_sec": 100, "total_sec": 0}
EOF

cat << 'EOF' > /app/corpus/evil/evil4.json
{"probe_id": 10, "token": 13370, "uptime_sec": -5, "total_sec": 3600}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
