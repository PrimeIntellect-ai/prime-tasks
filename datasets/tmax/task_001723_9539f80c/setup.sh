#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc ffmpeg
    pip3 install pytest

    mkdir -p /app
    echo "Emergency restore log. The base routing address is ten dot one hundred. The base health check port is eight thousand. Use these for the packet router reconstruction." | espeak -w /app/incident_report.wav

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    if (strlen(argv[1]) != 16) return 1;
    char h3[3] = {argv[1][0], argv[1][1], 0};
    char h4[3] = {argv[1][2], argv[1][3], 0};
    char hp[5] = {argv[1][12], argv[1][13], argv[1][14], argv[1][15], 0};
    int o3 = strtol(h3, NULL, 16) % 256;
    int o4 = strtol(h4, NULL, 16) % 256;
    int p = 8000 + strtol(hp, NULL, 16);
    printf("10.100.%d.%d:%d\n", o3, o4, p);
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/oracle_proxy_check
    strip /app/oracle_proxy_check
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
