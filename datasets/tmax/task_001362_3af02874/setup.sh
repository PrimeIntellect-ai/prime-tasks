#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_logger.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

void create_logs(const char* base_dir) {
    char path[256];
    sprintf(path, "mkdir -p %s/dirA/dirB", base_dir);
    system(path);
    sprintf(path, "mkdir -p %s/dirC", base_dir);
    system(path);

    int valid_count = 0;

    // File 1: Contains 50 valid records, 10 broken
    sprintf(path, "%s/dirA/file1.log", base_dir);
    FILE *f1 = fopen(path, "w");
    for(int i=0; i<60; i++) {
        fprintf(f1, "+-- BEGIN RECORD --+\n");
        fprintf(f1, "DATA: Payload %d\n", i);
        if (i % 6 != 0) {
            fprintf(f1, "+-- END RECORD --+\n");
            valid_count++;
        }
    }
    fclose(f1);

    // File 2: Contains 70 valid records, 20 broken
    sprintf(path, "%s/dirA/dirB/file2.log", base_dir);
    FILE *f2 = fopen(path, "w");
    for(int i=0; i<90; i++) {
        fprintf(f2, "+-- BEGIN RECORD --+\n");
        fprintf(f2, "DATA: Extra Payload %d\n", i);
        if (i % 4 != 0) { // 90 / 4 = 22. 90 - 23 = 67 + 1? Actually: 90/4 = 22 remainders.
            fprintf(f2, "+-- END RECORD --+\n");
        }
    }
    fclose(f2);
}

int main(int argc, char** argv) {
    if(argc != 2) return 1;
    create_logs(argv[1]);
    return 0;
}
EOF

    gcc -O3 -s /app/legacy_logger.c -o /app/legacy_logger
    strip --strip-all /app/legacy_logger
    rm /app/legacy_logger.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
