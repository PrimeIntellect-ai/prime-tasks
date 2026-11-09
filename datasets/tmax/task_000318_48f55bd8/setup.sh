#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/cred_svc

    cat << 'EOF' > /home/user/cred_svc/auth_helper.c
#include <stdio.h>
#include <string.h>

const char *backup_key = "BACKUP_9xQ2_fA11";

void read_token_file(const char *token_id) {
    char filepath[256];
    // Vulnerable to path traversal
    sprintf(filepath, "/var/tokens/%s", token_id);
    printf("Reading: %s\n", filepath);
}

int main(int argc, char **argv) {
    if (argc > 1) {
        read_token_file(argv[1]);
    }
    return 0;
}
EOF

    gcc /home/user/cred_svc/auth_helper.c -o /home/user/cred_svc/auth_helper

    cat << 'EOF' > /home/user/cred_svc/access.log
[2023-10-01T12:00:01] 192.168.1.10 - - Token_Request: my_token_1
[2023-10-01T12:05:00] 10.0.5.55 - - Token_Request: ../../../etc/passwd
[2023-10-01T12:10:00] 192.168.1.11 - - Token_Request: user_2_token
[2023-10-01T12:15:22] 172.16.0.4 - - Token_Request: ../../var/secret/master
[2023-10-01T12:16:00] 10.0.5.55 - - Token_Request: ../../etc/shadow
[2023-10-01T12:20:00] 192.168.1.15 - - Token_Request: normal_token_3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
