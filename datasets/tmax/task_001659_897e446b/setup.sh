#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        gcc

    pip3 install pytest

    # Create app directory
    mkdir -p /app/run

    # Generate the dashboard_spec.png image
    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -annotate +50+50 "FSTAB ENTRY:\ntmpfs /app/run tmpfs rw,nosuid,nodev,size=50m 0 0\n\nUPSTREAM SOCKET:\n/app/run/metrics.sock" \
        /app/dashboard_spec.png

    # Generate dummy access.log with 500,000 lines
    cat << 'EOF' > /tmp/gen_log.py
import random
with open('/app/access.log', 'w') as f:
    for i in range(500000):
        status = "200" if random.random() < 0.8 else "404"
        f.write(f'127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET / HTTP/1.0" {status} 2326\n')
EOF
    python3 /tmp/gen_log.py
    rm /tmp/gen_log.py

    # Create exporter.c
    cat << 'EOF' > /app/exporter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define SOCKET_PATH "/tmp/wrong_upstream.sock"

int main() {
    char buffer[1024];
    long total_requests = 0;

    // Simulate setting up a dummy server to accept the connection for the test
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sun_family = AF_UNIX;
    strncpy(server_addr.sun_path, "/app/run/metrics.sock", sizeof(server_addr.sun_path) - 1);
    unlink("/app/run/metrics.sock");
    bind(server_fd, (struct sockaddr*)&server_addr, sizeof(server_addr));
    listen(server_fd, 1);

    // Client connection
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        perror("Failed to connect to upstream socket");
        exit(1);
    }

    while (fgets(buffer, sizeof(buffer), stdin)) {
        total_requests++;
        // ARTIFICIAL BOTTLENECK TO BE REMOVED BY AGENT
        for (volatile int i = 0; i < 5000; i++); 
    }

    printf("Processed %ld requests\n", total_requests);
    close(fd);
    close(server_fd);
    return 0;
}
EOF

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
