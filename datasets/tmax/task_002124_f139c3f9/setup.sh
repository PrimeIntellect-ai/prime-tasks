#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

cat << 'EOF' > /app/legacy_router.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    // Dummy strings for analysis
    const char *s1 = "config";
    const char *s2 = "id";
    const char *s3 = "depth > 3";
    const char *s4 = "16 bytes";
    const char *s5 = "hexadecimal";
    printf("Processing %s\n", argv[1]);
    return 0;
}
EOF

gcc -o /app/legacy_router /app/legacy_router.c
strip /app/legacy_router
rm /app/legacy_router.c

cat << 'EOF' > /app/corpus/clean/clean_urls.txt
/api/v1/data?id=1a2b3c4d5e6f7a8b&config={"timeout":10}
/api/v1/auth?id=abcdef0123456789&config={"nested":{"level1":{"level2":"ok"}}}
EOF

cat << 'EOF' > /app/corpus/evil/evil_urls.txt
/api/v1/data?id=1a2b3c4d5e6f7a8z&config={"timeout":10}
/api/v1/data?id=1a2b3c4d5e6f7a8b&config={"nested":{"level1":{"level2":{"level3":"exploit"}}}}
/api/v1/data?id=invalid123456789&config={"timeout":10}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
