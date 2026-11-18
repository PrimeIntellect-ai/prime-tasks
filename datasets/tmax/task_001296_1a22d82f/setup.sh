#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/legacy_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>

int main() {
    char line[4096];
    regex_t regex_id, regex_x, regex_y;
    regcomp(&regex_id, "ID=([A-Z0-9]+)", REG_EXTENDED);
    regcomp(&regex_x, "X=([0-9]+\\.[0-9]+)", REG_EXTENDED);
    regcomp(&regex_y, "Y=([0-9]+\\.[0-9]+)", REG_EXTENDED);
    regmatch_t matches[2];

    while (fgets(line, sizeof(line), stdin)) {
        char id[64] = {0};
        double x = -1, y = -1;
        int found_id = 0, found_x = 0, found_y = 0;

        if (regexec(&regex_id, line, 2, matches, 0) == 0) {
            strncpy(id, line + matches[1].rm_so, matches[1].rm_eo - matches[1].rm_so);
            found_id = 1;
        }
        if (regexec(&regex_x, line, 2, matches, 0) == 0) {
            char temp[64] = {0};
            strncpy(temp, line + matches[1].rm_so, matches[1].rm_eo - matches[1].rm_so);
            x = atof(temp);
            found_x = 1;
        }
        if (regexec(&regex_y, line, 2, matches, 0) == 0) {
            char temp[64] = {0};
            strncpy(temp, line + matches[1].rm_so, matches[1].rm_eo - matches[1].rm_so);
            y = atof(temp);
            found_y = 1;
        }

        if (found_id && found_x && found_y) {
            double alpha = (x * x) + (2.0 * y);
            double beta = (x * y) - x;
            printf("%s,Alpha,%.2f\n", id, alpha);
            printf("%s,Beta,%.2f\n", id, beta);
        }
    }
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_processor.c -o /app/legacy_processor
    strip /app/legacy_processor
    rm /tmp/legacy_processor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
