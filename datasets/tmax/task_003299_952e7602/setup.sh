#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/processor.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char line[1024];
    // Dummy changepoint algorithm: flags lines containing "9.9"
    while (fgets(line, sizeof(line), stdin)) {
        if (strchr(line, '\n') == NULL) continue;
        if (strstr(line, "9.9") != NULL) {
            // Output dummy Unix timestamp and wide values
            printf("1697104800,9.9,1.1,2.2\n"); 
        }
    }
    return 0;
}
EOF
    gcc -O3 -s /tmp/processor.c -o /app/sensor_processor
    rm /tmp/processor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
