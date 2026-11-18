#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the C source file for the legacy binary
    cat << 'EOF' > /home/user/legacy_auth.c
#include <stdio.h>
#include <string.h>

const char fallback_key[] = "FBK_9x8u7y6t5r4e";

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], fallback_key) == 0) {
        printf("Authenticated with fallback key.\n");
        return 0;
    }
    printf("Access denied.\n");
    return 1;
}
EOF

    # Compile the binary
    gcc -O2 -o /home/user/legacy_auth /home/user/legacy_auth.c
    rm /home/user/legacy_auth.c

    # Generate the auth_events.log file
    cat << 'EOF' > /home/user/auth_events.log
[2023-10-01T10:00:00Z] IP=192.168.1.15 status="SUCCESS" cred="VALID_USER_1"
[2023-10-01T10:05:00Z] IP=10.0.5.22 status="FAILED" cred="FBK_9x8u7y6t5r4e"
[2023-10-01T10:12:00Z] IP=203.0.113.42 status="SUCCESS" cred="FBK_9x8u7y6t5r4e"
[2023-10-01T10:15:00Z] IP=198.51.100.7 status="SUCCESS" cred="VALID_USER_2"
[2023-10-01T10:20:00Z] IP=203.0.113.42 status="FAILED" cred="INVALID"
[2023-10-01T10:25:00Z] IP=104.28.14.16 status="SUCCESS" cred="FBK_9x8u7y6t5r4e"
[2023-10-01T10:30:00Z] IP=192.168.1.15 status="SUCCESS" cred="VALID_USER_1"
[2023-10-01T10:35:00Z] IP=203.0.113.42 status="SUCCESS" cred="FBK_9x8u7y6t5r4e"
[2023-10-01T10:40:00Z] IP=104.28.14.16 status="SUCCESS" cred="FBK_9x8u7y6t5r4e"
EOF

    chmod -R 777 /home/user
