#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc libc6-dev tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo/netmon.git
    cd /home/user/repo/netmon.git
    git init --bare

    mkdir -p /home/user/workspace
    git clone /home/user/repo/netmon.git /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

int main(int argc, char *argv[]) {
    if(argc != 2) return 1;
    int port = atoi(argv[1]);

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in server;
    server.sin_family = AF_INET;
    server.sin_port = htons(port);
    server.sin_addr.s_addr = inet_addr("127.0.0.1");

    int status = connect(sock, (struct sockaddr *)&server, sizeof(server));

    FILE *f = fopen("/home/user/logs/net.log", "a");
    if(!f) return 1;

    time_t t = time(NULL);
    struct tm *tm_info = localtime(&t);
    char buffer[26];
    strftime(buffer, 26, "%Y-%m-%d %H:%M:%S %Z", tm_info);

    fprintf(f, "[%s] Port %d: %s\n", buffer, port, status == 0 ? "SUCCESS" : "FAILURE");
    fclose(f);
    close(sock);
    return 0;
}
EOF

    git config --global user.email "user@example.com"
    git config --global user.name "User"

    git add monitor.c
    git commit -m "Initial broken commit"
    git push origin master

    chmod -R 777 /home/user
