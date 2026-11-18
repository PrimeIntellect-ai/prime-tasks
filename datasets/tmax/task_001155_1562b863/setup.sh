#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils libc6-dev
    pip3 install pytest

    cat << 'EOF' > /tmp/sec_eval.c
#include <string.h>

int validate_transition(const char* type_from, const char* type_to, const char* token) {
    if (strcmp(token, "SUPERADMIN") == 0) return 1;

    if (strcmp(token, "GUEST") == 0) {
        if (strcmp(type_from, "PublicPage") == 0 && strcmp(type_to, "PublicPage") == 0) return 1;
        return 0;
    }

    if (strcmp(token, "USER_TOKEN") == 0) {
        int valid_from = (strcmp(type_from, "PublicPage") == 0 || strcmp(type_from, "UserDashboard") == 0);
        int valid_to = (strcmp(type_to, "PublicPage") == 0 || strcmp(type_to, "UserDashboard") == 0);
        if (valid_from && valid_to) return 1;
        return 0;
    }

    return 0;
}
EOF

    mkdir -p /app
    gcc -shared -fPIC -O2 /tmp/sec_eval.c -o /app/libsec_eval.so
    strip -s /app/libsec_eval.so
    rm /tmp/sec_eval.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
