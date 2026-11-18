#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/_service/tmp
    mkdir -p /home/user/proxy/run
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/_service/daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define SOCKET_PATH "/home/user/_service/tmp/backend.sock"

int main() {
    int server_fd;
    struct sockaddr_un server_addr;

    // Remove existing socket if it exists
    unlink(SOCKET_PATH);

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        exit(EXIT_FAILURE);
    }

    memset(&server_addr, 0, sizeof(struct sockaddr_un));
    server_addr.sun_family = AF_UNIX;
    strncpy(server_addr.sun_path, SOCKET_PATH, sizeof(server_addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr *) &server_addr, sizeof(struct sockaddr_un)) < 0) {
        perror("bind");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 5) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    // Daemonize simulation (just sleep to keep the socket open)
    while(1) {
        sleep(10);
    }

    close(server_fd);
    unlink(SOCKET_PATH);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/proxy/check_upstream.sh
#!/bin/bash
if [ -z "$SOCKET_MAPPING_DIR" ]; then
    echo "500 Internal Server Error: SOCKET_MAPPING_DIR not set"
    exit 1
fi

if [ -S "$SOCKET_MAPPING_DIR/upstream.sock" ]; then
    echo "200 OK: Upstream connected"
    exit 0
else
    echo "502 Bad Gateway: Upstream socket not found"
    exit 1
fi
EOF

    chmod +x /home/user/proxy/check_upstream.sh

    chmod -R 777 /home/user
