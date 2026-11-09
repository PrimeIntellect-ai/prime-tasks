#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_filter.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        return 0;
    }
    char *str = argv[1];
    int len = strlen(str);
    if (len < 8) {
        printf("IGNORE\n");
        return 0;
    }
    int sum = 0;
    for (int i = 0; i < len; i++) {
        sum += (unsigned char)str[i];
    }
    if (strstr(str, "FATAL") != NULL) {
        sum += 500;
    }
    if (sum % 7 == 0) {
        printf("CRITICAL\n");
    } else if (sum % 3 == 0) {
        printf("WARNING\n");
    } else {
        printf("INFO\n");
    }
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_filter.c -o /app/legacy_filter
    strip /app/legacy_filter
    rm /tmp/legacy_filter.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
