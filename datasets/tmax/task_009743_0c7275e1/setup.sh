#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create auth.log
    cat << 'EOF' > /home/user/auth.log
[2023-10-01 10:00:01] 192.168.1.10 POST /login?next=/dashboard 200 "user=bob"
[2023-10-01 10:05:22] 10.0.0.5 POST /login?next=http://attacker.com/steal 200 "user=alice"
[2023-10-01 10:15:30] 192.168.1.11 POST /login?next=/profile 401 "user=dave"
[2023-10-01 10:20:11] 10.0.0.6 POST /login?next=https://evil.site.net/log 200 "user=charlie"
[2023-10-01 10:25:00] 192.168.1.12 POST /login?next=/settings 200 "user=eve"
EOF

    # Create users.txt
    cat << 'EOF' > /home/user/users.txt
alice:88dbba1b585721d60dbfc88c42ca519ebbcbe3e8ea210bb2da56ebf7004fbd77
bob:2f033a2e379469e71ec0a8c2f1ea0ddda0e3d100c500ab435ce82d02c842ba92
charlie:dbcc10b021d7b13ebbb77a456345ec48df08ff8be7d5668a0429a3fc300a894a
eve:3a4b5c1234567890abcdef1234567890abcdef1234567890abcdef1234567890
EOF

    # Create wordlist.txt
    cat << 'EOF' > /home/user/wordlist.txt
password123
qwerty
sunshine
dragon
letmein
admin
EOF

    # Create auth_server dummy binary
    cat << 'EOF' > /tmp/auth_server.c
#include <stdio.h>
int main() {
    const char *pepper = "S3cr3tP3pp3r2024";
    printf("Auth server running...\n");
    return 0;
}
EOF
    gcc /tmp/auth_server.c -o /home/user/auth_server
    rm /tmp/auth_server.c

    chmod -R 777 /home/user
