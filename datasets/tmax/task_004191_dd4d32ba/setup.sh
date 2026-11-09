#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc
    pip3 install pytest

    mkdir -p /home/user/data/docs/
    mkdir -p /app

    # Create SQLite database
    cat << 'EOF' > /home/user/data/init.sql
CREATE TABLE Observations (id TEXT PRIMARY KEY, category TEXT, timestamp TEXT);
INSERT INTO Observations VALUES ('obs_001', 'pulsar', '2023-01-01T12:00:00Z');
INSERT INTO Observations VALUES ('obs_002', 'pulsar', '2023-01-02T12:00:00Z');
INSERT INTO Observations VALUES ('obs_003', 'quasar', '2023-01-03T12:00:00Z');
EOF
    sqlite3 /home/user/data/catalog.db < /home/user/data/init.sql
    rm /home/user/data/init.sql

    # Create JSON documents
    cat << 'EOF' > /home/user/data/docs/obs_001.json
{"mass": 10.5, "spectral_class": "O"}
EOF

    cat << 'EOF' > /home/user/data/docs/obs_002.json
{"mass": 12.0, "spectral_class": "B"}
EOF

    cat << 'EOF' > /home/user/data/docs/obs_003.json
{"mass": 100.0, "spectral_class": "A"}
EOF

    # Create stripped C binary for relevance_scorer
    cat << 'EOF' > /app/scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("0.0\n");
        return 0;
    }
    char *json = argv[1];
    float mass = 0.0;
    int len = 0;

    char *mass_ptr = strstr(json, "\"mass\"");
    if (mass_ptr) {
        mass_ptr += 6;
        while (*mass_ptr == ' ' || *mass_ptr == ':') mass_ptr++;
        sscanf(mass_ptr, "%f", &mass);
    } else {
        printf("0.0\n");
        return 0;
    }

    char *sc_ptr = strstr(json, "\"spectral_class\"");
    if (sc_ptr) {
        sc_ptr += 16;
        while (*sc_ptr == ' ' || *sc_ptr == ':') sc_ptr++;
        if (*sc_ptr == '"') {
            sc_ptr++;
            char *end = strchr(sc_ptr, '"');
            if (end) {
                len = end - sc_ptr;
            }
        }
    } else {
        printf("0.0\n");
        return 0;
    }

    float score = (mass * 2.5) + (len * 1.5);
    printf("%f\n", score);
    return 0;
}
EOF

    gcc /app/scorer.c -o /app/relevance_scorer
    strip /app/relevance_scorer
    rm /app/scorer.c
    chmod +x /app/relevance_scorer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
