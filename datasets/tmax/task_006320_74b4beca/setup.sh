#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin /home/user/certs

    cat << 'EOF' > /home/user/system.log
[INFO] May 12 08:00:01 - System startup initiated
[INFO] May 12 08:00:05 - Starting backend services
[ERROR] May 12 08:00:06 - [PID 1042] /home/user/bin/legacy_worker: TLS Handshake aborted.
[ERROR] May 12 08:00:06 - [PID 1042] /home/user/bin/legacy_worker: Certificate validation failed.
[INFO] May 12 08:00:10 - Retry loop started for failed processes
EOF

    cat << 'EOF' > /tmp/dummy.c
#include <stdio.h>
int main() {
    const char* expected = "EXPECTED_CN=secops.internal.rotator.v1";
    printf("Starting worker... %s\n", expected);
    return 0;
}
EOF

    gcc /tmp/dummy.c -o /home/user/bin/legacy_worker
    rm /tmp/dummy.c

    chmod -R 777 /home/user
