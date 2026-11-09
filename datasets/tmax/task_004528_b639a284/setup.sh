#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat netcat-openbsd tar
    pip3 install pytest

    mkdir -p /home/user/archive
    mkdir -p /home/user/backend_service
    mkdir -p /home/user/restore_source/src

    cat << 'EOF' > /home/user/restore_source/src/multiplexer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>

int check_license() {
    struct tm exp = {0};
    exp.tm_year = 130; // 2030
    exp.tm_mon = 0;
    exp.tm_mday = 1;
    time_t exp_time = mktime(&exp);
    time_t now = time(NULL);
    return 1;
}

int main() {
    check_license();

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    int new_socket = accept(server_fd, NULL, NULL);
    char buffer[1024] = {0};
    read(new_socket, buffer, 1024);

    FILE *f = fopen("/home/user/restore/allowed_users.db", "r");
    char allowed = 0;
    if (f) {
        char line[256];
        while(fgets(line, sizeof(line), f)) {
            line[strcspn(line, "\r\n")] = 0;
            if(strcmp(line, "backup_operator") == 0) allowed = 1;
        }
        fclose(f);
    }

    if (!allowed) {
        write(new_socket, "DENIED\n", 7);
        return 1;
    }

    FILE *c = fopen("/home/user/restore/config.ini", "r");
    char sock_path[256] = {0};
    if (c) {
        fscanf(c, "upstream=%255s", sock_path);
        fclose(c);
    }

    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un serv_addr;
    serv_addr.sun_family = AF_UNIX;
    strcpy(serv_addr.sun_path, sock_path);
    connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr));

    write(sock, "PING\n", 5);
    char resp[1024] = {0};
    read(sock, resp, 1024);

    write(new_socket, resp, strlen(resp));
    close(new_socket);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/restore_source/config.ini
upstream=/var/run/backend.sock
EOF

    touch /home/user/restore_source/allowed_users.db

    cd /home/user/restore_source
    tar -czf /home/user/archive/multiplexer_backup.tar.gz .
    cd /home/user
    rm -rf /home/user/restore_source

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
