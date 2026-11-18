#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    # Create directories
    mkdir -p /app/email_quota_monitor-1.2.0/build
    mkdir -p /opt/legacy

    # Create broken Makefile
    cat << 'EOF' > /app/email_quota_monitor-1.2.0/Makefile
all:
    gcc -o build/eqm_util main.c
clean:
    rm -f build/eqm_util
EOF

    # Create broken main.c
    cat << 'EOF' > /app/email_quota_monitor-1.2.0/main.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    char *lvl = getenv("QUOTA_WARN_LVL");
    if (lvl != NULL) {
        printf("Warning Level: %s%%\n", lvl);
    } else {
        printf("Warning Level: Not Set\n");
    }
    return 0;
}
EOF

    # Create and compile oracle
    cat << 'EOF' > /tmp/quota_oracle.c
#include <stdio.h>

int main() {
    long long size;
    while (scanf("%lld", &size) == 1) {
        if (size > 1048576) {
            printf("EXCEEDED\n");
        } else {
            printf("OK\n");
        }
    }
    return 0;
}
EOF
    gcc -o /opt/legacy/quota_oracle /tmp/quota_oracle.c
    rm /tmp/quota_oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
