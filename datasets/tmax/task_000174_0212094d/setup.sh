#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb ltrace strace upx-ucl
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>
#include <ctype.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <payload>\n", argv[0]);
        return 1;
    }

    char *payload = argv[1];
    int len = strlen(payload);

    if (len < 8) {
        printf("REJECT: Too short\n");
        return 2;
    }

    for (int i = 0; i < 4; i++) {
        if (!isdigit((unsigned char)payload[i])) {
            printf("REJECT: Invalid PIN format\n");
            return 3;
        }
    }

    int d1 = payload[0] - '0';
    int d2 = payload[1] - '0';
    int d3 = payload[2] - '0';
    int d4 = payload[3] - '0';

    int hash = (d1 * 11 + d2 * 7 + d3 * 3 + d4) % 100;
    if (hash != 42) {
        printf("REJECT: Auth failed\n");
        return 4;
    }

    char *rest = payload + 4;
    if (strstr(rest, "<script>") || strstr(rest, "javascript:")) {
        printf("ALERT: XSS detected\n");
        return 5;
    }

    if (strstr(rest, "UNION SELECT") || strstr(rest, "' OR '1'='1")) {
        printf("ALERT: SQLi detected\n");
        return 6;
    }

    printf("PASS: Payload clean\n");
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/traffic_oracle
    strip /app/traffic_oracle
    upx /app/traffic_oracle || true
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
