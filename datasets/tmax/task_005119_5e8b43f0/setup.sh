#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/flag.txt
SECRET_FLAG_8f93a1b2c4d5e6f7
EOF

cat << 'EOF' > /home/user/auth_gw.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void execute_cmd(const char *cmd) {
    // Content Security Policy Filter
    if (strchr(cmd, ' ') != NULL || strstr(cmd, "cat") != NULL || strstr(cmd, "flag") != NULL) {
        printf("Security Policy Violation!\n");
        exit(1);
    }
    system(cmd);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <token_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        printf("Cannot open file.\n");
        return 1;
    }

    char buf[256];
    if (fgets(buf, sizeof(buf), f) == NULL) {
        fclose(f);
        return 1;
    }
    fclose(f);

    // Format: CMD|ALG|SIG
    char *cmd = strtok(buf, "|");
    char *alg = strtok(NULL, "|");
    char *sig = strtok(NULL, "\n");

    if (!cmd || !alg || !sig) {
        printf("Invalid token format.\n");
        return 1;
    }

    char expected_sig[64] = "SUPER_SECRET_SIGNATURE_KEY";

    // Flawed algorithm handling (alg=none bypass)
    if (strcmp(alg, "NONE") == 0) {
        expected_sig[0] = '\0';
    }

    // Vulnerability: strlen(expected_sig) is 0 if alg is NONE, causing strncmp to always return 0
    if (strncmp(sig, expected_sig, strlen(expected_sig)) == 0) {
        execute_cmd(cmd);
    } else {
        printf("Invalid signature!\n");
    }

    return 0;
}
EOF

gcc /home/user/auth_gw.c -o /home/user/auth_gw

chmod -R 777 /home/user
