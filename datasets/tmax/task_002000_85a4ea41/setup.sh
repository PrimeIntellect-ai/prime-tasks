#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential curl
    pip3 install pytest

    mkdir -p /app

    # Create the mock C daemon
    cat << 'EOF' > /tmp/daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <socket_path> <data_csv>\n", argv[0]);
        return 1;
    }
    srand(time(NULL));
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, argv[1], sizeof(addr.sun_path)-1);
    unlink(argv[1]);
    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind");
        return 1;
    }
    listen(server_fd, 10);
    while(1) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd > 0) {
            unsigned char buf[5];
            int n = read(client_fd, buf, 5);
            if (n == 5 && buf[0] == 0x01) {
                // Simulate deadlock randomly
                if (rand() % 3 == 0) {
                    unsigned char err = 0xFF;
                    write(client_fd, &err, 1);
                } else {
                    char resp[256];
                    // Return mock node IDs
                    sprintf(resp, "%d,%d,%d\n", buf[2], buf[2]+1, buf[2]+2);
                    write(client_fd, resp, strlen(resp));
                }
            }
            close(client_fd);
        }
    }
    return 0;
}
EOF

    gcc -O2 /tmp/daemon.c -o /app/graph_daemon
    strip /app/graph_daemon
    rm /tmp/daemon.c

    useradd -m -s /bin/bash user || true

    # Create dummy dataset
    cat << 'EOF' > /home/user/data.csv
1,2
2,3
3,4
4,1
EOF

    chmod -R 777 /home/user
