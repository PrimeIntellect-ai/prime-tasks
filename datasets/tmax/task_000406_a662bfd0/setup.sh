#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/bin

    cat << 'EOF' > /tmp/tracker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

void trim_newline(char *str) {
    int len = strlen(str);
    while (len > 0 && (str[len-1] == '\n' || str[len-1] == '\r')) {
        str[len-1] = '\0';
        len--;
    }
}

int main() {
    char line[2048];
    char file[2048] = {0};
    char status[2048] = {0};
    int has_file = 0;
    int has_status = 0;

    while (fgets(line, sizeof(line), stdin)) {
        trim_newline(line);
        char *p = line;
        while (*p && isspace((unsigned char)*p)) p++;

        if (*p == '\0') {
            if (has_file && has_status && strcmp(status, "OK") != 0) {
                printf("TRACK %s -> %s\n", file, status);
            }
            has_file = 0;
            has_status = 0;
            file[0] = '\0';
            status[0] = '\0';
        } else {
            if (strncmp(p, "FILE:", 5) == 0) {
                char *val = p + 5;
                while (*val && isspace((unsigned char)*val)) val++;
                strcpy(file, val);
                has_file = 1;
            } else if (strncmp(p, "STATUS:", 7) == 0) {
                char *val = p + 7;
                while (*val && isspace((unsigned char)*val)) val++;
                strcpy(status, val);
                has_status = 1;
            }
        }
    }
    if (has_file && has_status && strcmp(status, "OK") != 0) {
        printf("TRACK %s -> %s\n", file, status);
    }

    return 0;
}
EOF

    gcc -O2 /tmp/tracker.c -o /app/bin/tracker_parser
    strip /app/bin/tracker_parser
    rm /tmp/tracker.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
