#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/forensics

    cat << 'EOF' > /home/user/forensics/parser.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void extract_ip(const char *log_line, FILE *out) {
    char ip[16]; // 15 chars max for IPv4 (e.g. 255.255.255.255) + 1 for null terminator
    const char *ip_start = strstr(log_line, "SRC=");
    if (ip_start) {
        ip_start += 4;
        int i = 0;

        // BUG: i <= 15 allows 16 characters to be read.
        // If the string doesn't have a space and is 16+ chars long, 
        // i becomes 16, and ip[16] = '\0' causes an out-of-bounds write.
        while (ip_start[i] != ' ' && ip_start[i] != '\n' && ip_start[i] != '\0' && i <= 15) {
            ip[i] = ip_start[i];
            i++;
        }
        ip[i] = '\0';
        fprintf(out, "%s\n", ip);
    }
}

int main(int argc, char **argv) {
    if (argc != 2) {
        printf("Usage: %s <logfile>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("Failed to open file");
        return 1;
    }
    FILE *out = fopen("parsed_ips.txt", "w");
    if (!out) {
        perror("Failed to open output");
        return 1;
    }
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        extract_ip(line, out);
    }
    fclose(f);
    fclose(out);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/forensics/auth.log
Feb 14 10:00:01 firewall kernel: DROP IN=eth0 OUT= SRC=192.168.1.100 DST=10.0.0.1
Feb 14 10:05:22 firewall kernel: DROP IN=eth0 OUT= SRC=10.5.5.5 DST=10.0.0.1
Feb 14 10:12:00 firewall kernel: DROP IN=eth0 OUT= SRC=255.255.255.255 DST=10.0.0.1
Feb 14 10:15:30 firewall kernel: DROP IN=eth0 OUT= SRC=192.168.111.2222 DST=10.0.0.1
Feb 14 10:20:00 firewall kernel: DROP IN=eth0 OUT= SRC=172.16.0.1 DST=10.0.0.1
EOF

    chmod -R 777 /home/user
