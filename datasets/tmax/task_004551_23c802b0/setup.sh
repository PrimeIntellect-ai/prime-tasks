#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install packages needed for the task
    apt-get install -y gcc iptables iproute2 netcat-openbsd socat expect parallel

    # Create the mock binary
    mkdir -p /app
    cat << 'EOF' > /tmp/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <fcntl.h>

int main() {
    char path[1024];
    printf("Manifest path? > ");
    fflush(stdout);
    if (fgets(path, sizeof(path), stdin) == NULL) return 1;
    path[strcspn(path, "\n")] = 0;

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock >= 0) {
        struct sockaddr_in serv_addr;
        serv_addr.sin_family = AF_INET;
        serv_addr.sin_port = htons(8080);
        inet_pton(AF_INET, "10.254.254.10", &serv_addr.sin_addr);

        int flags = fcntl(sock, F_GETFL, 0);
        fcntl(sock, F_SETFL, flags | O_NONBLOCK);
        connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr));

        fd_set fdset;
        struct timeval tv;
        FD_ZERO(&fdset);
        FD_SET(sock, &fdset);
        tv.tv_sec = 2;
        tv.tv_usec = 0;
        select(sock + 1, NULL, &fdset, NULL, &tv);
        close(sock);
    }

    char out_path[1024];
    snprintf(out_path, sizeof(out_path), "%s.opt.yaml", path);

    FILE *f = fopen(path, "r");
    if (f) {
        FILE *out = fopen(out_path, "w");
        if (out) {
            char buffer[4096];
            size_t bytes;
            while ((bytes = fread(buffer, 1, sizeof(buffer), f)) > 0) {
                fwrite(buffer, 1, bytes, out);
            }
            fprintf(out, "\n# Processed\n");
            fclose(out);
        }
        fclose(f);
    }

    printf("Done.\n");
    return 0;
}
EOF
    gcc -O2 /tmp/main.c -o /app/k8s-manifest-processor
    strip /app/k8s-manifest-processor
    rm /tmp/main.c

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/manifests/raw

    chmod -R 777 /home/user
