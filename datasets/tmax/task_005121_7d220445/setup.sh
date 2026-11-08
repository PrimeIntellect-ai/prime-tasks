#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect gcc gdb binutils netcat-openbsd strace openssh-server file
    pip3 install pytest

    # Create users
    useradd -m -s /bin/bash user || true
    useradd -m -s /bin/bash monitor_user || true
    echo "monitor_user:monitor_pass" | chpasswd

    # Setup sshd
    mkdir -p /run/sshd
    ssh-keygen -A

    # Setup /app/prober
    mkdir -p /app
    cat << 'EOF' > /app/prober.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int sock = 0;
    struct sockaddr_in serv_addr;
    char buffer[1024] = {0};

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) return -1;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(8080);
    if(inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr)<=0) return -1;
    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) return -1;

    send(sock, "HELO PROBE_SYS_v2\n", 18, 0);
    read(sock, buffer, 1024);
    send(sock, "METRIC CPU_USAGE 85\n", 20, 0);
    read(sock, buffer, 1024);
    send(sock, "BYE\n", 4, 0);
    close(sock);
    return 0;
}
EOF
    gcc -o /app/prober /app/prober.c
    strip /app/prober
    rm /app/prober.c

    chmod -R 777 /home/user
