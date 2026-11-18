#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/service.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

void handle_client(int client_sock) {
    char request_buffer[128];
    // Vulnerability: read can overflow the 128-byte buffer
    int bytes_read = read(client_sock, request_buffer, 512);
    if (bytes_read > 0) {
        printf("Received: %s\n", request_buffer);
        write(client_sock, "ACK\n", 4);
    }
    close(client_sock);
}

int main() {
    int server_fd, client_sock;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8888);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        client_sock = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        handle_client(client_sock);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/traffic_dump.txt
00000000  41 41 41 41 41 41 41 41  41 41 41 41 41 41 41 41  |AAAAAAAAAAAAAAAA|
*
00000080  41 41 41 41 41 41 41 41  42 42 42 42 42 42 42 42  |AAAAAAAABBBBBBBB|
00000090  48 31 c0 50 48 bf 2f 2f  62 69 6e 2f 73 68 57 48  |H1.PH.//bin/shWH|
000000a0  89 e7 50 48 89 e2 57 48  89 e6 b0 3b 0f 05        |..PH..WH...;..|
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/src
    chown user:user /home/user/traffic_dump.txt
    chmod -R 777 /home/user
