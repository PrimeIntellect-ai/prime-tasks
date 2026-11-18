#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev gzip make
    pip3 install pytest

    mkdir -p /app/verifier/evil_corpus
    mkdir -p /app/verifier/clean_corpus
    mkdir -p /home/user/dataset/raw/subdir1
    mkdir -p /home/user/dataset/raw/subdir2

    # Create sensor_parser.c
    cat << 'EOF' > /app/sensor_parser.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    int fault = 0;
    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\r\n")] = 0;
        if (strcmp(line, "STATUS: FAULT") == 0) fault = 1;
        if (strcmp(line, "OVERRIDE: TRUE") == 0) fault = 0;
    }
    fclose(f);
    if (fault) return 139;
    return 0;
}
EOF

    gcc -O2 -s /app/sensor_parser.c -o /app/sensor_parser
    rm /app/sensor_parser.c

    # Create evil corpus
    cat << 'EOF' > /app/verifier/evil_corpus/evil1.txt
BEGIN_RECORD
TIMESTAMP: 1700000000
SENSOR_ID: 42
STATUS: FAULT
END_RECORD
EOF

    cat << 'EOF' > /app/verifier/evil_corpus/evil2.txt
BEGIN_RECORD
TIMESTAMP: 1700000001
SENSOR_ID: 43
STATUS: FAULT
OTHER: DATA
END_RECORD
EOF

    # Create clean corpus
    cat << 'EOF' > /app/verifier/clean_corpus/clean1.txt
BEGIN_RECORD
TIMESTAMP: 1700000002
SENSOR_ID: 44
STATUS: OK
END_RECORD
EOF

    cat << 'EOF' > /app/verifier/clean_corpus/clean2.txt
BEGIN_RECORD
TIMESTAMP: 1700000003
SENSOR_ID: 45
STATUS: FAULT
OVERRIDE: TRUE
END_RECORD
EOF

    # Create dataset raw logs
    cat << 'EOF' > /home/user/dataset/raw/subdir1/log1.log
BEGIN_RECORD
TIMESTAMP: 1700000010
SENSOR_ID: 1
STATUS: OK
END_RECORD
BEGIN_RECORD
TIMESTAMP: 1700000011
SENSOR_ID: 2
STATUS: FAULT
END_RECORD
EOF
    gzip /home/user/dataset/raw/subdir1/log1.log

    cat << 'EOF' > /home/user/dataset/raw/subdir2/log2.log
BEGIN_RECORD
TIMESTAMP: 1700000012
SENSOR_ID: 3
STATUS: FAULT
OVERRIDE: TRUE
END_RECORD
EOF
    gzip /home/user/dataset/raw/subdir2/log2.log

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
