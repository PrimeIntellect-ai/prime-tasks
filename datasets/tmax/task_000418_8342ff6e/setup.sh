#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

double min_val(double a, double b) { return a < b ? a : b; }
double max_val(double a, double b) { return a > b ? a : b; }

int main() {
    char line[4096];
    int is_header = 1;
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = 0;
        if (is_header) {
            printf("%s,posterior\n", line);
            is_header = 0;
            continue;
        }

        char text_data[2048];
        double prior = 0.0;

        char *comma = strrchr(line, ',');
        if (!comma) continue;

        *comma = '\0';
        strcpy(text_data, line);
        prior = atof(comma + 1);

        double p = prior;

        char *token = strtok(text_data, "|");
        while (token != NULL) {
            int len = strlen(token);
            double l_pos = len / 100.0;
            l_pos = min_val(l_pos, 0.99);
            l_pos = max_val(0.01, l_pos);
            double l_neg = 1.0 - l_pos;

            double num = p * l_pos;
            double den = (p * l_pos) + ((1.0 - p) * l_neg);
            if (den != 0.0) {
                p = num / den;
            }

            token = strtok(NULL, "|");
        }

        printf("%s,%g,%.4f\n", line, prior, p);
    }
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/risk_oracle
    strip /app/risk_oracle
    chmod +x /app/risk_oracle
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
