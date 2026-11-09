#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils strace gdb
    pip3 install pytest

    mkdir -p /app

    # Create dummy backup file
    dd if=/dev/urandom of=/app/backup.dat bs=1024 count=1

    # Create the C source for the restore agent
    cat << 'EOF' > /tmp/restore_agent.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <sys/stat.h>
#include <limits.h>

int main(int argc, char *argv[]) {
    char *key = getenv("RESTORE_MASTER_KEY");
    if (!key || strcmp(key, "drill_token_8891") != 0) {
        fprintf(stderr, "Unauthorized\n");
        return 1;
    }

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return 1;

    struct sockaddr_in server;
    server.sin_family = AF_INET;
    server.sin_port = htons(7777);
    server.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (connect(sock, (struct sockaddr *)&server, sizeof(server)) < 0) {
        fprintf(stderr, "Daemon connection failed\n");
        return 1;
    }

    char *msg = "STATUS: READY_TO_RESTORE\n";
    send(sock, msg, strlen(msg), 0);

    char buf[256] = {0};
    int n = recv(sock, buf, sizeof(buf)-1, 0);
    if (n <= 0 || strcmp(buf, "CMD: PROCEED\n") != 0) {
        fprintf(stderr, "Daemon rejected\n");
        return 1;
    }

    char *out_dir = ".";
    if (argc > 2) {
        out_dir = argv[2];
    }

    mkdir(out_dir, 0777);

    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/manifest.json", out_dir);
    FILE *f1 = fopen(path, "w");
    if (f1) {
        fprintf(f1, "{\"backup_id\": 9942, \"status\": \"verified\"}");
        fclose(f1);
    }

    snprintf(path, sizeof(path), "%s/data.csv", out_dir);
    FILE *f2 = fopen(path, "w");
    if (f2) {
        fprintf(f2, "id,value\n1,alpha\n2,beta\n");
        fclose(f2);
    }

    printf("Restore successful\n");
    return 0;
}
EOF

    # Compile and strip the binary
    gcc /tmp/restore_agent.c -o /app/restore_agent
    strip /app/restore_agent
    rm /tmp/restore_agent.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
