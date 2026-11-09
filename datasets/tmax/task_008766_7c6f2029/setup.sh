#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo
    pip3 install pytest

    mkdir -p /home/user

    # Create auth.log
    cat << 'EOF' > /home/user/auth.log
[2023-10-01T12:00:00Z] SUCCESS User alice login attempt with hash: 1111111111111111111111111111111111111111111111111111111111111111
[2023-10-01T12:05:00Z] SUCCESS User admin login attempt with hash: 9a2f7c087cf51c1ff7825d19bf9b9fbfa7f339cf5c6bf1b0388d71da5ba16886
[2023-10-01T12:10:00Z] FAILED User bob login attempt with hash: 2222222222222222222222222222222222222222222222222222222222222222
EOF

    # Create cmdlines.txt
    cat << 'EOF' > /home/user/cmdlines.txt
/usr/bin/auth_worker --mode validate --token password123 --user bob
/usr/bin/auth_worker --mode validate --token super_secret_token_99 --user admin
/usr/bin/auth_worker --mode validate --token qwerty --user alice
/usr/bin/auth_worker --mode validate --token myvoiceismypassport --user unknown
EOF

    # Compile auth_daemon
    cat << 'EOF' > /tmp/auth.c
#include <stdio.h>
const char* hidden_salt = "SALT_X9k2mP";
int main() {
    printf("Auth Daemon Running...\n");
    return 0;
}
EOF
    gcc /tmp/auth.c -o /home/user/auth_daemon
    rm /tmp/auth.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
