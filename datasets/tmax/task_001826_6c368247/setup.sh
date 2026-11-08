#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create the legacy parser C source
    cat << 'EOF' > /app/legacy_parser.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

int main() {
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), stdin)) {
        int len = strlen(buffer);
        if (len > 0 && buffer[len-1] == '\n') {
            buffer[len-1] = '\0';
            len--;
        }

        if (len > 255) {
            fprintf(stderr, "Crash: Buffer overflow!\n");
            abort();
        }

        char *ptr = strstr(buffer, "ADMIN_BYPASS=true");
        if (ptr != NULL) {
            int non_alnum = 0;
            char *p = ptr - 1;
            while (p >= buffer && !isalnum((unsigned char)*p)) {
                non_alnum++;
                p--;
            }
            if (non_alnum >= 3) {
                fprintf(stderr, "Crash: Logic bypass!\n");
                abort();
            }
        }

        printf("%s\n", buffer);
    }
    return 0;
}
EOF

    gcc -O2 -s -o /app/legacy_parser /app/legacy_parser.c
    rm /app/legacy_parser.c

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/sample1.log
2023-10-01 12:00:00 INFO User logged in
2023-10-01 12:05:00 DEBUG Processing request 12345
2023-10-01 12:10:00 WARN Disk space running low
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/sample1.log
2023-10-01 12:15:00 ERROR Malicious attempt ***ADMIN_BYPASS=true detected
EOF

    # Create a > 255 chars line
    python3 -c "print('A' * 256)" > /app/corpora/evil/sample2.log

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.config/systemd/user
    cat << 'EOF' > /home/user/.config/systemd/user/log-pipeline.service
[Unit]
Description=Log Pipeline Service

[Service]
ExecStart=/bin/bash -c "cat /tmp/stream | /app/legacy_parser"
Restart=always

[Install]
WantedBy=default.target
EOF

    chmod -R 777 /home/user
