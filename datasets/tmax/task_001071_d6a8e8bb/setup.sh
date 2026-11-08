#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat
    pip3 install pytest

    mkdir -p /home/user/obs_stack

    cat << 'EOF' > /home/user/obs_stack/telemetry_server.py
import socket
import time
import sys

time.sleep(2) # Simulate slow startup
HOST = '127.0.0.1'
PORT = 9090

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.bind((HOST, PORT))
    s.listen()
    conn, addr = s.accept()
    with conn:
        conn.sendall(b"cpu_usage=42% mem_usage=60%\n")
EOF

    cat << 'EOF' > /home/user/obs_stack/aggregator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int sock = 0;
    struct sockaddr_in serv_addr;
    char buffer[1024] = {0};

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        printf("\n Socket creation error \n");
        return -1;
    }

    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(8080);

    if (inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr) <= 0) {
        printf("\nInvalid address/ Address not supported \n");
        return -1;
    }

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        printf("\nConnection Failed \n");
        return -1;
    }

    read(sock, buffer, 1024);

    FILE *f = fopen("/home/user/obs_stack/dashboard.log", "w");
    if (f) {
        fprintf(f, "[SUCCESS] Metrics received: %s", buffer);
        fclose(f);
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/obs_stack/start.sh
#!/bin/bash
python3 /home/user/obs_stack/telemetry_server.py &
# Missing port forward setup
/home/user/obs_stack/aggregator
EOF
    chmod +x /home/user/obs_stack/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
