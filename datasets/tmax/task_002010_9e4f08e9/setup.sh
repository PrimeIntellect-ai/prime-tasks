#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest

    mkdir -p /app
    mkdir -p /test_data
    mkdir -p /home/user

    # Create legacy scanner C code
    cat << 'EOF' > /tmp/legacy_scanner.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <openssl/md5.h>

void to_upper(char *str) {
    for (int i = 0; str[i]; i++) {
        str[i] = toupper(str[i]);
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\r\n")] = 0;
        if (strlen(line) == 0) continue;

        char *sep1 = strstr(line, " | ");
        if (!sep1) continue;
        char *sep2 = strstr(sep1 + 3, " | ");
        if (!sep2) continue;

        *sep1 = 0;
        *sep2 = 0;
        char *id = line;
        char *hash = sep1 + 3;
        char *payload = sep2 + 3;

        unsigned char digest[MD5_DIGEST_LENGTH];
        MD5((unsigned char*)payload, strlen(payload), digest);
        char md5string[33];
        for(int i = 0; i < 16; ++i)
            sprintf(&md5string[i*2], "%02x", (unsigned int)digest[i]);

        if (strcmp(hash, md5string) != 0) {
            printf("%s: INTEGRITY_FAIL\n", id);
            continue;
        }

        char payload_upper[4096];
        strncpy(payload_upper, payload, sizeof(payload_upper));
        to_upper(payload_upper);

        if (strstr(payload_upper, "UNION SELECT") || strstr(payload_upper, "DROP TABLE")) {
            printf("%s: INTRUSION_DETECTED\n", id);
        } else {
            printf("%s: CLEAN\n", id);
        }
    }
    fclose(f);
    return 0;
}
EOF

    # Compile and strip the legacy scanner
    gcc -w -O3 -o /app/legacy_scanner /tmp/legacy_scanner.c -lcrypto
    strip /app/legacy_scanner

    # Generate logs
    cat << 'EOF' > /tmp/gen_logs.py
import hashlib
import random

def gen_logs(filename, count):
    with open(filename, 'w') as f:
        for i in range(count):
            id_str = f"LOG{i:05d}"

            p_type = random.choice(['clean', 'clean', 'clean', 'sql1', 'sql2', 'fail'])

            if p_type == 'clean':
                payload = f"User login successful for user_{random.randint(1, 1000)}"
            elif p_type == 'sql1':
                payload = f"SELECT * FROM users WHERE id=1 UNION SELECT username, password FROM admin"
            elif p_type == 'sql2':
                payload = f"admin'; DROP TABLE users; --"
            else:
                payload = f"Some random data {random.randint(1, 1000)}"

            md5 = hashlib.md5(payload.encode()).hexdigest()

            if p_type == 'fail':
                md5 = "0" * 32

            f.write(f"{id_str} | {md5} | {payload}\n")

gen_logs('/home/user/sample_logs.txt', 100)
gen_logs('/test_data/hidden_logs.txt', 10000)
EOF

    python3 /tmp/gen_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /test_data
    chmod -R 777 /app
