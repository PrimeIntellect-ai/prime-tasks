#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest websockets

    # Create project directories
    mkdir -p /home/user/project/src

    # Create sanitizer.c
    cat << 'EOF' > /home/user/project/src/sanitizer.c
#include <string.h>

int is_safe_payload(const char* payload) {
    if (strstr(payload, "<script>") != NULL) return 0;
    if (strstr(payload, "DROP TABLE") != NULL) return 0;
    if (strstr(payload, "OR 1=1") != NULL) return 0;
    return 1;
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
