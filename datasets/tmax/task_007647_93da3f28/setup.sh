#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc iputils-ping procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/managed_users/alice
    mkdir -p /home/user/managed_users/bob
    mkdir -p /home/user/managed_users/charlie
    mkdir -p /home/user/active_links

    echo "127.0.0.1" > /home/user/managed_users/alice/node.txt
    echo "198.51.100.254" > /home/user/managed_users/bob/node.txt
    echo "127.0.0.1" > /home/user/managed_users/charlie/node.txt

    cat << 'EOF' > /home/user/dummy_worker.c
#include <unistd.h>
int main() {
    while(1) { sleep(10); }
    return 0;
}
EOF

    gcc /home/user/dummy_worker.c -o /home/user/worker_alice
    gcc /home/user/dummy_worker.c -o /home/user/worker_bob
    gcc /home/user/dummy_worker.c -o /home/user/worker_charlie

    # Start workers in bashrc so they are running when tests/agent run
    echo "/home/user/worker_alice >/dev/null 2>&1 &" >> /home/user/.bashrc
    echo "/home/user/worker_bob >/dev/null 2>&1 &" >> /home/user/.bashrc
    echo "/home/user/worker_alice >/dev/null 2>&1 &" >> /etc/bash.bashrc
    echo "/home/user/worker_bob >/dev/null 2>&1 &" >> /etc/bash.bashrc

    chmod -R 777 /home/user
