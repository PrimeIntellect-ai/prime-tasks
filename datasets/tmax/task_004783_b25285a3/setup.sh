#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest requests flask

    mkdir -p /app/src /app/bin /app/data /app/migrations /app/service /app/logs

    cat << 'EOF' > /app/src/libaudiofeat.c
#include <stdio.h>

float get_audio_feature(const char* filepath) {
    FILE *f = fopen(filepath, "rb");
    if(!f) return -1.0;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fclose(f);
    // Dummy feature: file size modulo 1000 + 0.5
    return (float)(size % 1000) + 0.5f;
}
EOF

    cat << 'EOF' > /app/migrations/001_init.sql
CREATE TABLE jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    filepath TEXT NOT NULL
);
EOF

    cat << 'EOF' > /app/migrations/002_add_columns.sql
ALTER TABLE jobs ADD COLUMN feature_value REAL;
ALTER TABLE jobs ADD COLUMN status TEXT;
EOF

    dd if=/dev/urandom of=/app/test_audio.wav bs=1024 count=1

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
