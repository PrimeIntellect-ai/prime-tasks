#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/auth_daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_auth(const char *user, const char *pass) {
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "/usr/local/bin/check_user --auth-method legacy -U '%s' -P '%s'", user, pass);
    system(cmd);
}

int main(int argc, char **argv) {
    if (argc == 3) {
        process_auth(argv[1], argv[2]);
    }
    return 0;
}
EOF
    gcc -o /app/auth_daemon /tmp/auth_daemon.c
    strip /app/auth_daemon
    chmod +x /app/auth_daemon
    rm /tmp/auth_daemon.c

    mkdir -p /opt/verifier/corpus/evil
    mkdir -p /opt/verifier/corpus/clean

    cat << 'EOF' > /opt/verifier/corpus/evil/evil1.json
["/bin/sh", "-c", "/usr/local/bin/check_user --auth-method legacy -U 'admin' -P 'secret123'"]
EOF
    cat << 'EOF' > /opt/verifier/corpus/evil/evil2.json
["/bin/sh", "-c", "/usr/local/bin/check_user --auth-method legacy -U 'admin' ; cat /etc/shadow ; echo '1' -P 'none'"]
EOF

    cat << 'EOF' > /opt/verifier/corpus/clean/clean1.json
["/bin/bash", "-c", "echo hello"]
EOF
    cat << 'EOF' > /opt/verifier/corpus/clean/clean2.json
["/bin/sh", "-c", "/usr/local/bin/check_user --auth-method new -U 'admin' -P 'secret'"]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
