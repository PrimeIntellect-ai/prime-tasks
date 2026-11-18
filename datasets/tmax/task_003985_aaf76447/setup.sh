#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc tesseract-ocr imagemagick
pip3 install pytest

mkdir -p /app
echo "FLAG{RBAC_BYPASS_SUCCESS}" > /app/flag.txt

cat << 'EOF' > /app/sec_broker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void grant_access() {
    FILE *f = fopen("/app/flag.txt", "r");
    if (f) {
        char buf[128];
        if (fgets(buf, sizeof(buf), f)) {
            printf("%s", buf);
        }
        fclose(f);
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    struct {
        char buf[32];
        unsigned int role;
    } data;

    data.role = 0;

    fread(data.buf, 1, 64, f);
    fclose(f);

    unsigned int salt;
    memcpy(&salt, data.buf, 4);

    if (salt != 0x5A17) {
        return 1;
    }

    if (data.role == 0xDEADBEEF) {
        grant_access();
    }

    return 0;
}
EOF

gcc -fno-stack-protector -o /app/sec_broker /app/sec_broker.c

cat << 'EOF' > /app/legacy_auth.c
#include <stdio.h>
int main() {
    unsigned int backdoor_role = 0xDEADBEEF;
    printf("Legacy auth check. Offset 32 required to be %x\n", backdoor_role);
    return 0;
}
EOF
gcc -o /app/legacy_auth /app/legacy_auth.c

convert -pointsize 24 label:"MASTER SALT: 0x5A17" /app/diagram.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
