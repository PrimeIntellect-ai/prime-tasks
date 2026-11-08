#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sqlite3 golang-go
    pip3 install pytest

    mkdir -p /home/user/telemetry
    cd /home/user/telemetry

    # Create dummy raw data
    echo "BIN_DATA_00101010" > /home/user/telemetry/raw.dat

    # Create the C header
    cat << 'EOF' > /home/user/telemetry/telemetry.h
#ifndef TELEMETRY_H
#define TELEMETRY_H

int process_telemetry(const char* input_file, char* output_buffer, int max_len);

#endif
EOF

    # Create the C source
    cat << 'EOF' > /home/user/telemetry/telemetry.c
#include "telemetry.h"
#include <string.h>

int process_telemetry(const char* input_file, char* output_buffer, int max_len) {
    const char* result = "{\"device\": \"Pixel 7\", \"build_time\": 145.2, \"memory_used\": 4096, \"battery_drain\": 1.5}";
    if (strlen(result) < max_len) {
        strcpy(output_buffer, result);
        return 0;
    }
    return -1;
}
EOF

    # Create the broken Makefile
    cat << 'EOF' > /home/user/telemetry/Makefile
libtelemetry.so: telemetry.c
	gcc -o libtelemetry.so telemetry.c
EOF

    # Setup the SQLite database with the old schema
    sqlite3 /home/user/metrics.db "CREATE TABLE builds (id INTEGER PRIMARY KEY, device TEXT, build_time REAL);"
    sqlite3 /home/user/metrics.db "INSERT INTO builds (device, build_time) VALUES ('iPhone 13', 120.5);"

    # Ensure go environment is initialized
    cd /home/user/telemetry
    go mod init telemetry
    go get github.com/mattn/go-sqlite3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
