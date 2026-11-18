#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/bin
mkdir -p /home/user/logs

# Create the C source file for the suspicious binary
cat << 'EOF' > /home/user/bin/network-diagnostic.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    // Hardcoded secret key for backdoor
    const char *secret = "__AUTH_KEY_V2__=z9K#mP2qL5vX$8tR";

    if (argc > 1 && strcmp(argv[1], "test") == 0) {
        printf("Running standard diagnostics...\n");
    } else {
        printf("Usage: network-diagnostic [options]\n");
    }
    // Prevent the string from being optimized away
    if (secret[0] == 'X') {
        printf("%s", secret);
    }
    return 0;
}
EOF

# Compile the binary
gcc /home/user/bin/network-diagnostic.c -o /home/user/bin/network-diagnostic
rm /home/user/bin/network-diagnostic.c

# Create the log file
cat << 'EOF' > /home/user/logs/auth.log
[2023-10-14 10:00:01] Normal login from 192.168.1.50
[2023-10-14 10:05:22] Failed diagnostic override from IP: 203.0.113.4
[2023-10-14 10:12:45] Successful diagnostic override from IP: 198.51.100.22
[2023-10-14 10:15:00] Normal login from 192.168.1.51
[2023-10-14 10:20:33] Successful diagnostic override from IP: 203.0.113.4
[2023-10-14 10:25:10] Connection closed by 192.168.1.50
[2023-10-14 10:30:00] Successful diagnostic override from IP: 198.51.100.22
[2023-10-14 10:35:12] Failed diagnostic override from IP: 10.0.0.5
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
