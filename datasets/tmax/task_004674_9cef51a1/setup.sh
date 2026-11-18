#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils strace iptables
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/evil /app/corpus/clean
    mkdir -p /home/user/.ssh

    # Create dummy C program for the legacy CGI binary
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char *target = NULL;
    if (argc > 1) {
        target = argv[1];
    } else {
        char buffer[1024];
        if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
            target = buffer;
        }
    }
    if (!target) return 0;

    // Vulnerable patterns
    if (strstr(target, "../")) {
        system("cat ../../etc/passwd > /dev/null 2>&1");
    }
    if (strchr(target, ';') || strchr(target, '|') || strchr(target, '&') || strchr(target, '`')) {
        system(target);
    }
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -o /app/legacy_cgi /tmp/legacy.c
    strip /app/legacy_cgi
    rm /tmp/legacy.c
    chmod +x /app/legacy_cgi

    # Create clean corpus files
    echo -e "GET /index.cgi?target=homepage HTTP/1.1\nHost: example.com\n" > /app/corpus/clean/req1.txt
    echo -e "POST /index.cgi HTTP/1.1\nHost: example.com\n\ntarget=12345" > /app/corpus/clean/req2.txt

    # Create evil corpus files
    echo -e "GET /index.cgi?target=../../etc/passwd HTTP/1.1\nHost: example.com\n" > /app/corpus/evil/req1.txt
    echo -e "POST /cgi-bin/test HTTP/1.1\nHost: example.com\n\ntarget=127.0.0.1;cat /etc/shadow" > /app/corpus/evil/req2.txt
    echo -e "GET /index.cgi?target=index.html|ls HTTP/1.1\nHost: example.com\n" > /app/corpus/evil/req3.txt
    echo -e "GET /index.cgi?target=index.html&whoami HTTP/1.1\nHost: example.com\n" > /app/corpus/evil/req4.txt
    echo -e "GET /index.cgi?target=\`id\` HTTP/1.1\nHost: example.com\n" > /app/corpus/evil/req5.txt

    # Create dummy authorized_keys for testing
    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC dummy-rsa-key user1@host
ssh-dss AAAAB3NzaC1kc3MAAACBA dummy-dss-key user2@host
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI dummy-ed25519-key user3@host
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABB dummy-ecdsa-key user4@host
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/.ssh
    chmod -R 777 /home/user
