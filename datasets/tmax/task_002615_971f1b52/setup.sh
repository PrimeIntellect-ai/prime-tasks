#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron gawk sed libc-bin
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /data

    # Create and compile the legacy ETL binary
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        char *id_s = strtok(line, ",");
        char *cat = strtok(NULL, ",");
        char *val = strtok(NULL, ",");
        char *notes = strtok(NULL, ""); // Rest of line

        if (!id_s || !cat || !val || !notes) continue;

        int id = atoi(id_s);
        if (id % 10 != 0) continue;

        if (strlen(val) == 0) {
            val = "0.0";
        }

        // Emulate ISO-8859-1 to UTF-8
        printf("%d,%s,%s,", id, cat, val);
        for(int i=0; notes[i] != '\0'; i++) {
            unsigned char c = (unsigned char)notes[i];
            if (c < 128) {
                putchar(c);
            } else {
                putchar(0xC2 + (c > 191));
                putchar((c & 0x3F) | 0x80);
            }
        }
        printf("\n");
    }
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/legacy_etl
    strip /app/legacy_etl
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true

    chmod -R 777 /app
    chmod -R 777 /data
    chmod -R 777 /home/user
