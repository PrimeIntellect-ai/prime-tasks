#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    apt-get install -y build-essential valgrind jq bc gawk patch

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/api_backend

    cat << 'EOF' > /home/user/api_backend/process_data.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main() {
    char buffer[4096];
    if (!fgets(buffer, sizeof(buffer), stdin)) return 1;

    char *start = strchr(buffer, '[');
    char *end = strchr(buffer, ']');
    if (!start || !end) return 1;
    *end = '\0';
    start++;

    int capacity = 10;
    double *values = malloc(capacity * sizeof(double));
    int count = 0;

    char *token = strtok(start, ", ");
    while (token) {
        if (count >= capacity) {
            capacity *= 2;
            values = realloc(values, capacity * sizeof(double));
        }
        values[count++] = atof(token);
        token = strtok(NULL, ", ");
    }

    double sum_sq = 0.0;
    for (int i = 0; i < count; i++) {
        sum_sq += values[i] * values[i];
    }
    double norm = sqrt(sum_sq);

    printf("{\"norm\": %.4f}\n", norm);

    // BUG: Missing free(values);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/input_data.txt
-3.5
4.2
-1.1
7.8
-5.0
EOF

    chown -R user:user /home/user/api_backend /home/user/input_data.txt
    chmod -R 777 /home/user
