#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/attack_logs.dat
IP:192.168.1.100:ATTACK:SQL_INJECTION:
IP:10.0.0.5:ATTACK:CROSS_SITE_SCRIPTING_XSS:
IP:172.16.0.42:ATTACK:REMOTE_CODE_EXECUTION:
EOF

    cat << 'EOF' > /home/user/parse_logs.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    FILE *f = fopen("/home/user/attack_logs.dat", "r");
    if (!f) {
        printf("Could not open input file\n");
        return 1;
    }

    FILE *out = fopen("/home/user/malicious_ips.txt", "w");
    if (!out) {
        printf("Could not open output file\n");
        return 1;
    }

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char token[16]; // BUG: Buffer is too small for attack types like CROSS_SITE_SCRIPTING_XSS (24 chars)
        int t_idx = 0;
        int state = 0; // 0=seeking IP label, 1=reading IP, 2=seeking ATTACK label, 3=reading attack type
        char current_ip[64] = {0};

        for(int i = 0; line[i] != '\0' && line[i] != '\n'; i++) {
            if(line[i] == ':') {
                token[t_idx] = '\0';

                if (state == 0 && strcmp(token, "IP") == 0) {
                    state = 1;
                } else if (state == 1) {
                    strcpy(current_ip, token);
                    state = 2;
                } else if (state == 2 && strcmp(token, "ATTACK") == 0) {
                    state = 3;
                } else if (state == 3) {
                    fprintf(out, "Detected %s from %s\n", token, current_ip);
                    state = 0;
                }
                t_idx = 0;
            } else {
                token[t_idx++] = line[i];
            }
        }
    }

    fclose(f);
    fclose(out);
    return 0;
}
EOF

    chmod -R 777 /home/user
