#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil

cat << 'EOF' > /app/obfuscator.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        char buffer[1024];
        if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
            buffer[strcspn(buffer, "\n")] = 0;
            int len = strlen(buffer);
            printf("ATTK_");
            for (int i = len - 1; i >= 0; i--) {
                unsigned char c = buffer[i] ^ 0x37;
                printf("%02x", c);
            }
            printf("\n");
            return 0;
        }
        return 1;
    }
    char *input = argv[1];
    int len = strlen(input);
    printf("ATTK_");
    for (int i = len - 1; i >= 0; i--) {
        unsigned char c = input[i] ^ 0x37;
        printf("%02x", c);
    }
    printf("\n");
    return 0;
}
EOF

gcc -O2 /app/obfuscator.c -o /app/obfuscator
strip -s /app/obfuscator
rm /app/obfuscator.c

python3 -c '
import os

def obfuscate(s):
    rev = s[::-1]
    xored = [ord(c) ^ 0x37 for c in rev]
    hexed = "".join([f"{c:02x}" for c in xored])
    return "ATTK_" + hexed

clean_data = [
    "id=42",
    "search=apples",
    "page=about",
    "user=john",
    "action=login"
]

evil_data = [
    "id=" + obfuscate("1=1"),
    "search=" + obfuscate("<script>alert(1)</script>"),
    "page=" + obfuscate("admin\" OR 1=1--"),
    "user=" + obfuscate("admin"),
    "action=" + obfuscate("drop table users;")
]

with open("/app/corpora/clean/clean.txt", "w") as f:
    f.write("\n".join(clean_data) + "\n")

with open("/app/corpora/evil/evil.txt", "w") as f:
    f.write("\n".join(evil_data) + "\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
