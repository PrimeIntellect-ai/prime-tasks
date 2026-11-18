#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app

    cat << 'EOF' > /app/legacy_etl.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[256];
    char history[10][256];
    int count = 0;
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (strlen(line) == 0) continue;
        char id[50], name[50], email[100], ssn[50];
        if (sscanf(line, "%49[^,],%49[^,],%99[^,],%49s", id, name, email, ssn) == 4) {
            char json[512];
            sprintf(json, "{\"record_id\":\"%s\",\"name\":\"%s\",\"email\":\"%s\",\"ssn\":\"%s\"}\n", id, name, email, ssn);
            printf("%s", json);
            strcpy(history[count % 10], json);
            count++;

            // simulate retry duplication
            if (count % 3 == 0 && count > 1) {
                printf("%s", history[(count-2) % 10]);
                printf("%s", history[(count-1) % 10]);
            }
        }
    }
    return 0;
}
EOF

    gcc -O2 -s /app/legacy_etl.c -o /app/legacy_etl
    rm /app/legacy_etl.c
    chmod +x /app/legacy_etl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
