#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/vuln_service.c
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    // The decoded trigger string
    if (strcmp(argv[1], "AlphaBravoCharlie99!") == 0) {
        if (fork() == 0) {
            // Child process leaks the flag in cmdline and sleeps briefly
            execlp("sleep", "sleep", "0.5", "FLAG{pr0c_cmdl1n3_l34k_m4st3r}", NULL);
            exit(0);
        }
    }
    return 0;
}
EOF

    gcc -o /home/user/vuln_service /home/user/vuln_service.c
    rm /home/user/vuln_service.c
    chmod +x /home/user/vuln_service

    cat << 'EOF' > /home/user/audit.log
[2023-10-25 14:22:01] INFO Connection established from 192.168.1.105
[2023-10-25 14:22:05] WARNING Suspicious input detected on port 8080
[2023-10-25 14:22:06] ALERT Trigger sequence captured. Payload (Base64): QWxwaGFCcmF2b0NoYXJsaWU5OSE=
[2023-10-25 14:22:06] INFO Connection closed.
EOF

    chmod -R 777 /home/user
