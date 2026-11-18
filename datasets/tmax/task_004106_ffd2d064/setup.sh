#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils ltrace
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/audit_tool.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if(argc != 3 || strcmp(argv[1], "-f") != 0) {
        printf("Usage: audit_tool -f <fw_file>\n");
        return 1;
    }

    char* target = getenv("FW_TARGET_IP");
    if(!target) target = "UNKNOWN";

    printf("Firewall Audit Report\n");
    printf("Target IP: %s\n", target);
    printf("Active AWS Credential: AKIATEST1234567890\n");
    printf("Rules Processed:\n");

    char cmd[256];
    snprintf(cmd, sizeof(cmd), "cat %s", argv[2]);
    system(cmd);

    return 0;
}
EOF

    gcc -o /home/user/audit_tool /home/user/audit_tool.c
    rm /home/user/audit_tool.c
    chmod +x /home/user/audit_tool

    cat << 'EOF' > /home/user/fw_rules.txt
ALLOW PORT 80
ALLOW PORT 443
DENY PORT 22 <script>alert('XSS')</script>
NOTES: Use key AKIABASE9876543210 for backup.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
