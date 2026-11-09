#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/target_csp_daemon.c
#include <stdio.h>
#include <string.h>

void generate_nonce() {
    // The hardcoded seed string
    const char* secret_seed = "RED_TEAM_SEED_X9_2024_!@#";
    printf("Nonce seed is loaded.\n");
    // In a real binary, this would compute the SHA256 and output it.
}

int main() {
    generate_nonce();
    return 0;
}
EOF
    gcc /tmp/target_csp_daemon.c -o /home/user/target_csp_daemon
    rm /tmp/target_csp_daemon.c
    chmod +x /home/user/target_csp_daemon

    chmod -R 777 /home/user
