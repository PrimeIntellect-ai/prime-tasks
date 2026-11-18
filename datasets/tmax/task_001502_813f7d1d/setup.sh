#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk coreutils
    pip3 install pytest flask fastapi uvicorn

    mkdir -p /home/user
    mkdir -p /app

    # Create raw_logs.csv with UTF-16LE encoding
    python3 -c '
import codecs
content = """Timestamp,UserID,Message
"1696161600","U001","First message"
"10/01/2023 12:00:00","U001","Duplicate message"
"1696165200","U002","Line 1\nLine 2\nLine 3"
"""
with open("/home/user/raw_logs.csv", "wb") as f:
    f.write(content.encode("utf-16-le"))
'

    # Create the legacy_hasher "compiled binary"
    cat << 'EOF' > /app/legacy_hasher.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *input = argv[1];
    char *cmd = malloc(strlen(input) + 100);
    sprintf(cmd, "printf '%%s_S4LTY' \"%s\" | md5sum | awk '{printf $1}'", input);
    system(cmd);
    free(cmd);
    printf("\n");
    return 0;
}
EOF
    gcc /app/legacy_hasher.c -o /app/legacy_hasher
    rm /app/legacy_hasher.c
    chmod +x /app/legacy_hasher

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
