#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libseccomp-dev openssl sudo util-linux
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    cat << 'EOF' > /home/user/legacy_auditd.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>

void compliance_flag_reached() {
    FILE *f = fopen("/home/user/audit_flag.txt", "w");
    if (f) {
        fprintf(f, "COMPLIANCE_AUDIT_PASSED_XYZ123\n");
        fclose(f);
    }
    printf("Compliance flag generated.\n");
    exit(0);
}

void process_log_entry() {
    char buffer[64];
    printf("Enter log entry: ");
    gets(buffer); // VULNERABILITY: Buffer overflow
    printf("Logged: %s\n", buffer);
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "test_net") == 0) {
        // Dummy socket call to test seccomp sandbox
        int s = socket(AF_INET, SOCK_STREAM, 0);
        if (s < 0) {
            printf("Socket blocked!\n");
            exit(1);
        }
        printf("Socket allowed!\n");
        exit(0);
    }
    process_log_entry();
    return 0;
}
EOF
    chown user:user /home/user/legacy_auditd.c
    chmod -R 777 /home/user
