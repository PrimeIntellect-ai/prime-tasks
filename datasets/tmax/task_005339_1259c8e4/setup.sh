#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gcc binutils
    pip3 install pytest

    # Create app directory
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create dummy ssh_auditor binary
    cat << 'EOF' > /tmp/ssh_auditor.c
#include <stdio.h>
int main() {
    char buf[2048];
    while(fgets(buf, sizeof(buf), stdin)) {
        printf("May 10 12:00:01|192.168.1.1|publickey|Accepted|SHA256:abcdefg\n");
    }
    return 0;
}
EOF
    gcc /tmp/ssh_auditor.c -o /app/ssh_auditor
    strip /app/ssh_auditor
    chmod +x /app/ssh_auditor
    rm /tmp/ssh_auditor.c

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/input.txt
May 10 12:00:01|192.168.1.1|publickey|Accepted|SHA256:abcdefg
May 10 12:00:02|10.0.0.5|password|Failed|NONE
May 10 12:00:03|192.168.1.2|publickey|Failed|SHA256:xyz123
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/input.txt
May 10 12:01:01|10.10.10.10|publickey|Failed|SHA256:abc;reboot
May 10 12:01:02|10.10.10.11|publickey|Failed|SHA256:xyz|curl
May 10 12:01:03|10.10.10.12|publickey|Failed|SHA256:123$USER
May 10 12:01:04|10.10.10.13|publickey|Failed|SHA256:test>out
May 10 12:01:05|10.10.10.14|publickey|Failed|SHA256:test<in
May 10 12:01:06|10.10.10.15|publickey|Failed|SHA256:test&bg
EOF

    chmod -R 755 /app

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
