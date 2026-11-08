#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev cron socat netcat-openbsd curl file dos2unix
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/mock.c
#include <stdio.h>
#include <string.h>

int main() {
    char line[1024];
    while(fgets(line, sizeof(line), stdin)) {
        if(strchr(line, '\0') != NULL && strchr(line, '\0') < line + strlen(line)) {
            continue; // drop null bytes
        }
        if(strstr(line, "\n") != NULL && line[strlen(line)-1] != '\n') {
            // embedded newline logic simplified for the mock
        }
        printf("%s", line);
    }
    return 0;
}
EOF

    gcc -O2 -s -o /app/config_processor /tmp/mock.c
    chmod +x /app/config_processor
    rm /tmp/mock.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
