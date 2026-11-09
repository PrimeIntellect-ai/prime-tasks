#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/alert-router.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[1024];
    int has_mailing_list = 0;
    int has_valid_url = 0;

    while (fgets(line, sizeof(line), f)) {
        int len = strlen(line);
        if (len == 64) {
            int *p = NULL;
            *p = 1;
        }
        if (strncmp(line, "[MailingList]", 13) == 0) {
            has_mailing_list = 1;
        }
        if (strncmp(line, "HealthCheckURL=", 15) == 0) {
            char *url = line + 15;
            if (strncmp(url, "https://", 8) == 0) {
                if (strstr(url, "localhost") != NULL) {
                    exit(3);
                }
                has_valid_url = 1;
            } else {
                exit(2);
            }
        }
    }
    fclose(f);

    if (!has_mailing_list) exit(1);
    if (!has_valid_url) exit(2);

    return 0;
}
EOF

    gcc -O2 -s -o /app/alert-router /app/alert-router.c
    rm /app/alert-router.c

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/example_configs
    cat << 'EOF' > /home/user/example_configs/working.txt
[MailingList]
HealthCheckURL=https://example.com/health
EOF

    cat << 'EOF' > /home/user/example_configs/crashing.txt
[MailingList]
HealthCheckURL=https://example.com/health
123456789012345678901234567890123456789012345678901234567890123
EOF

    mkdir -p /var/opt/verifier/corpus/clean
    mkdir -p /var/opt/verifier/corpus/evil

    cat << 'EOF' > /var/opt/verifier/corpus/clean/1.txt
[MailingList]
HealthCheckURL=https://example.com/health
EOF

    cat << 'EOF' > /var/opt/verifier/corpus/evil/1.txt
[MailingList]
HealthCheckURL=http://example.com/health
EOF

    cat << 'EOF' > /var/opt/verifier/corpus/evil/2.txt
[MailingList]
HealthCheckURL=https://localhost/health
EOF

    cat << 'EOF' > /var/opt/verifier/corpus/evil/3.txt
[MailingList]
HealthCheckURL=https://example.com/health
123456789012345678901234567890123456789012345678901234567890123
EOF

    chmod -R 777 /home/user
