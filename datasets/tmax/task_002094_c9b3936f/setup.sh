#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip festival festvox-kdlpc16k zip unzip gcc
    pip3 install pytest

    mkdir -p /app
    echo "crimson butterfly" | text2wave -o /app/voicemail.wav

    mkdir -p /app/evidence/logs
    cat << 'EOF' > /app/evidence/logs/auth.log
Sep 14 10:00:01 server sshd[1234]: Failed password for root from 192.168.1.10 port 33411 ssh2
Sep 14 10:05:22 server sshd[1235]: Accepted password for root from 10.5.22.109 port 49112 ssh2
Sep 14 10:05:22 server sshd[1235]: pam_unix(sshd:session): session opened for user root by (uid=0)
EOF

    cat << 'EOF' > /tmp/backdoor.c
#include <stdio.h>
const char* port_config = "LISTEN_PORT=8443";
int main() {
    printf("Backdoor running...\n");
    return 0;
}
EOF
    gcc /tmp/backdoor.c -o /app/evidence/backdoor_bin
    rm /tmp/backdoor.c

    cd /app/evidence
    zip -r -P "crimson butterfly" ../evidence.zip *
    cd /
    rm -rf /app/evidence

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
