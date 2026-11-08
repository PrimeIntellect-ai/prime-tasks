#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git
    pip3 install pytest psutil

    # Create the C binary
    mkdir -p /app
    cat << 'EOF' > /app/poly_solver.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    char buf[1024];
    while(fgets(buf, sizeof(buf), stdin)) {
        printf("1.0+0.0j\n");
        fflush(stdout);
    }
    return 0;
}
EOF
    gcc -O2 /app/poly_solver.c -o /app/poly_solver
    strip /app/poly_solver
    chmod 644 /app/poly_solver
    rm /app/poly_solver.c

    # Create the Python service repository
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/poly_service
    cd /home/user/poly_service

    cat << 'EOF' > server.py
import socket
import subprocess
import os
import sys

SOCK_PATH = "/tmp/poly.sock"
BINARY_PATH = "/app/poly_solver"

audit_log = []

def handle_client(conn):
    data = conn.recv(1024)
    if not data:
        return

    try:
        proc = subprocess.Popen([BINARY_PATH], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        out, _ = proc.communicate(data.decode())

        # LOG_HOOK

        conn.sendall(out.encode())
    except Exception as e:
        conn.sendall(str(e).encode())

def main():
    if os.path.exists(SOCK_PATH):
        os.remove(SOCK_PATH)

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCK_PATH)
    server.listen(5)

    while True:
        conn, _ = server.accept()
        handle_client(conn)
        conn.close()

if __name__ == "__main__":
    main()
EOF

    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # Commit 1
    git add server.py
    git commit -m "Initial commit: basic server"
    git tag v1.0-stable

    # Commits 2-11
    for i in $(seq 2 11); do
        echo "# Comment $i" >> server.py
        git add server.py
        git commit -m "Minor update $i"
    done

    # Commit 12: Introduce memory leak
    sed -i 's/# LOG_HOOK/audit_log.append(data.decode() * 1000)/' server.py
    git add server.py
    git commit -m "Add audit logging for requests"

    # Commits 13-20
    for i in $(seq 13 20); do
        echo "# Comment $i" >> server.py
        git add server.py
        git commit -m "Minor update $i"
    done

    chown -R user:user /home/user/poly_service
    chmod -R 777 /home/user
