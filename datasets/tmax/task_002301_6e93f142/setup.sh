#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # 1. Create the legacy binary with a hardcoded string
    cat << 'EOF' > legacy.c
#include <stdio.h>
int main() {
    const char* staging_ca = "https://staging-ca.internal.net/cert.pem";
    printf("Legacy inspector initialized.\n");
    return 0;
}
EOF
    gcc legacy.c -o legacy_inspector
    rm legacy.c

    # 2. Create the flawed traffic_inspector.c
    cat << 'EOF' > traffic_inspector.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void redact_ssn(char *payload) {
    char *pos = strstr(payload, "SSN: ");
    if (pos != NULL) {
        // Flawed redaction: only redacts the first 3 chars
        strncpy(pos + 5, "XXX", 3);
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    // Buffer overflow vulnerability (CWE-120)
    char buffer[128];
    char temp[1024] = {0};
    fread(temp, 1, 1023, f);
    fclose(f);

    // Flaw: strcpy from larger temp into smaller buffer
    strcpy(buffer, temp);

    redact_ssn(buffer);

    // Missing CSP prepending
    printf("%s", buffer);

    return 0;
}
EOF

    # 3. Create raw_traffic.txt
    cat << 'EOF' > raw_traffic.txt
HTTP/1.1 200 OK
Content-Type: text/plain

User Account Details:
Name: John Doe
SSN: 987-65-4321
Status: Active
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
