#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        make \
        sqlite3 \
        libsqlite3-dev \
        gawk \
        coreutils

    pip3 install pytest numpy

    # Create directories
    mkdir -p /app/bash-ds-utils/src
    mkdir -p /app/bash-ds-utils/bin
    mkdir -p /home/user/data/clean
    mkdir -p /home/user/data/evil

    # Create the perturbed Makefile
    cat << 'EOF' > /app/bash-ds-utils/Makefile
CC=/usr/bin/false
CFLAGS=-O2

all: bin/track_exp

bin/track_exp: src/track_exp.c
	mkdir -p bin
	$(CC) $(CFLAGS) -o bin/track_exp src/track_exp.c -lsqlite3

install: all
EOF

    # Create perturbed setup_env.sh
    cat << 'EOF' > /app/bash-ds-utils/setup_env.sh
export TRACKER_HOME=/nonexistent
EOF

    # Create dummy C tracker
    cat << 'EOF' > /app/bash-ds-utils/src/track_exp.c
#include <stdio.h>
#include <string.h>
#include <sqlite3.h>

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "--init") == 0) {
        sqlite3 *db;
        int rc = sqlite3_open("tracker.db", &db);
        if (rc) {
            return 1;
        }
        sqlite3_close(db);
        return 0;
    }
    return 0;
}
EOF

    # Generate test corpora using Python
    python3 -c "
import os
import numpy as np

# Clean data: 50 files, 50 dimensions, distance to 0.1s around 10.0
# distance = sqrt(50 * (x - 0.1)^2) = 10 => (x - 0.1)^2 = 2 => x ~ 1.514
for i in range(50):
    data = np.random.normal(1.514, 0.1, (100, 50))
    np.savetxt(f'/home/user/data/clean/file_{i}.tsv', data, delimiter='\t')

# Evil data: 50 files
for i in range(50):
    if i < 15:
        # 49 cols
        data = np.random.normal(1.514, 0.1, (100, 49))
    elif i < 30:
        # 51 cols
        data = np.random.normal(1.514, 0.1, (100, 51))
    elif i < 40:
        # distance > 20 => (x - 0.1)^2 > 8 => x > 2.93
        data = np.random.normal(3.0, 0.1, (100, 50))
    else:
        # distance < 2.0 => (x - 0.1)^2 < 0.08 => x < 0.38
        data = np.random.normal(0.38, 0.01, (100, 50))
    np.savetxt(f'/home/user/data/evil/file_{i}.tsv', data, delimiter='\t')
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
