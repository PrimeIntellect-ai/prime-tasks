#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/incident

cat << 'EOF' > /home/user/incident/auth.log
Sep 24 10:20:01 server sshd[1011]: Accepted publickey for admin from 192.168.1.10 port 50123 ssh2
Sep 24 10:21:15 server sudo[1022]: admin : TTY=pts/0 ; PWD=/home/admin ; USER=root ; COMMAND=/bin/ls
Sep 24 10:25:01 server auth_helper[1255]: FAILED: Elevation denied for 'guest' from IP '10.0.2.15'
Sep 24 10:28:44 server auth_helper[1301]: SUCCESS: Root elevation granted to user 'www-data' from IP '10.0.5.55' using target checksum '0x15e'
Sep 24 10:30:00 server sshd[1340]: Disconnected from user admin 192.168.1.10 port 50123
EOF

cat << 'EOF' > /home/user/incident/auth_helper.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// Simulated auth helper
int main(int argc, char** argv) {
    if (argc != 2) {
        printf("Usage: %s <token>\n", argv[0]);
        return 1;
    }

    const char* token = argv[1];

    // Token must have prefix
    if (strncmp(token, "ADM-", 4) != 0) {
        printf("Invalid prefix.\n");
        return 1;
    }

    int checksum = 0;
    // Calculate custom checksum on the rest of the string
    for (int i = 4; i < strlen(token); i++) {
        checksum += token[i];
    }

    // 0x15e is 350 in decimal
    if (checksum == 0x15e) {
        printf("AUTH_SUCCESS\n");
        return 0;
    }

    printf("AUTH_FAILED\n");
    return 1;
}
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/incident
chmod -R 777 /home/user
