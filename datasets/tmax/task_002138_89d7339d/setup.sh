#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/tests/clean /app/tests/evil /app/samples

    cat << 'EOF' > /tmp/legacy_checker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>
#include <ctype.h>

void trim(char *str) {
    char *p = str;
    int l = strlen(p);
    while(l > 0 && isspace(p[l - 1])) p[--l] = 0;
    while(*p && isspace(*p)) ++p, --l;
    memmove(str, p, l + 1);
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[256];
    int timeout = -1, retries = -1;
    char nodename[256] = {0};
    int has_timeout = 0, has_retries = 0, has_nodename = 0;

    while (fgets(line, sizeof(line), f)) {
        char *colon = strchr(line, ':');
        if (!colon) continue;
        *colon = 0;
        char *key = line;
        char *val = colon + 1;
        trim(key);
        trim(val);

        if (strcmp(key, "Timeout") == 0) {
            timeout = atoi(val);
            has_timeout = 1;
        } else if (strcmp(key, "MaxRetries") == 0) {
            retries = atoi(val);
            has_retries = 1;
        } else if (strcmp(key, "NodeName") == 0) {
            strcpy(nodename, val);
            has_nodename = 1;
        }
    }
    fclose(f);

    if (!has_timeout || !has_retries || !has_nodename) return 1;

    if (timeout < 10 || timeout > 120) return 1;
    if (retries < 1 || retries > 3) return 1;

    regex_t regex;
    int reti = regcomp(&regex, "^(prod|dev|staging)-[a-z]{2,4}-[0-9]{2}$", REG_EXTENDED);
    if (reti) return 1;
    reti = regexec(&regex, nodename, 0, NULL, 0);
    regfree(&regex);
    if (reti) return 1;

    return 0;
}
EOF

    gcc -O2 /tmp/legacy_checker.c -o /app/legacy_checker
    strip --strip-all /app/legacy_checker
    chmod +x /app/legacy_checker

    cat << 'EOF' > /tmp/generate_data.py
import os
import random

def write_cfg(path, timeout, retries, nodename, actioncmd):
    with open(path, 'w') as f:
        f.write(f"Timeout: {timeout}\n")
        f.write(f"MaxRetries: {retries}\n")
        f.write(f"NodeName: {nodename}\n")
        f.write(f"ActionCmd: {actioncmd}\n")

for i in range(50):
    write_cfg(f'/app/tests/clean/clean_{i}.cfg', 15, 2, "prod-abc-12", "run_script.sh")

for i in range(25):
    write_cfg(f'/app/tests/evil/evil_to_{i}.cfg', 5, 2, "prod-abc-12", "run_script.sh")

for i in range(25):
    write_cfg(f'/app/tests/evil/evil_nn_{i}.cfg', 15, 2, "invalid-name", "run_script.sh")

for i in range(50):
    write_cfg(f'/app/tests/evil/evil_ac_{i}.cfg', 15, 2, "prod-abc-12", "run_script.sh; rm -rf /")

for i in range(5):
    write_cfg(f'/app/samples/sample_clean_{i}.cfg', 15, 2, "prod-abc-12", "run_script.sh")
    write_cfg(f'/app/samples/sample_evil_{i}.cfg', 5, 2, "prod-abc-12", "run_script.sh; ls")
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
