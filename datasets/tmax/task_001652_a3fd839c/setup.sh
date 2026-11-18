#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential tar
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create auth log
    cat << 'EOF' > /home/user/auth.log
May 14 10:20:01 host sshd[123]: Failed password for service_account from 203.0.113.5 port 55432 ssh2
May 14 10:20:05 host sshd[124]: Failed password for service_account from 198.51.100.42 port 44321 ssh2
May 14 10:20:10 host sshd[125]: Accepted password for service_account from 198.51.100.42 port 44321 ssh2
May 14 10:21:00 host sshd[126]: Failed password for service_account from 198.51.100.42 port 44321 ssh2
EOF

    # Create evidence dir
    mkdir -p /home/user/evidence

    # Download and setup darkhttpd
    mkdir -p /app
    cd /app
    wget https://github.com/emikulic/darkhttpd/archive/refs/tags/v1.14.tar.gz
    tar -xzf v1.14.tar.gz
    rm v1.14.tar.gz

    cd darkhttpd-1.14
    # Perturb Makefile
    if grep -q "^CC = cc" Makefile; then
        sed -i 's/^CC = cc/CC = invalid_compiler_name/' Makefile
    elif grep -q "^CC ?= cc" Makefile; then
        sed -i 's/^CC ?= cc/CC = invalid_compiler_name/' Makefile
    else
        sed -i '1i CC = invalid_compiler_name' Makefile
    fi

    # Perturb darkhttpd.c
    sed -i '/static void process_request/a \    if (strstr("dummy", "X-Attacker-Auth: backdoor")) { /* bypass */ }' darkhttpd.c

    chmod -R 777 /home/user
    chmod -R 777 /app
