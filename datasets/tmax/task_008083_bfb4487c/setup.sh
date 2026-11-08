#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar gzip
    pip3 install pytest

    mkdir -p /home/user/src
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/experiment_data.txt
EXP_101 S S F S F S S S
EXP_102 F F F S F
EXP_103 S S S S S S S S S S
EXP_104 F S
EOF

    cat << 'EOF' > /home/user/src/analyze.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    FILE *in = fopen("/home/user/experiment_data.txt", "r");
    FILE *out = fopen("/home/user/artifacts/results.csv", "w");

    if (!in || !out) {
        printf("Error opening files.\n");
        return 1;
    }

    char line[256];
    while (fgets(line, sizeof(line), in)) {
        // Remove newline
        line[strcspn(line, "\n")] = 0;

        // Tokenize
        char *exp_id = strtok(line, ","); // BUG: Delimiter should be " "
        if (!exp_id) continue;

        int count_s = 0;
        int count_f = 0;

        char *token;
        while ((token = strtok(NULL, " ")) != NULL) {
            if (strcmp(token, "S") == 0) count_s++;
            else if (strcmp(token, "F") == 0) count_f++;
        }

        // Bayesian calculation with Beta(1,1) prior
        // BUG: Integer division will result in 0
        float posterior = (count_s + 1) / (count_s + count_f + 2);

        fprintf(out, "%s,%.4f\n", exp_id, posterior);
    }

    fclose(in);
    fclose(out);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
