#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/libstatscsv-1.0
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create vendored library
    cat << 'EOF' > /app/vendored/libstatscsv-1.0/statscsv.h
#ifndef STATSCSV_H
#define STATSCSV_H

typedef struct {
    char **tokens;
    int count;
} CSVRow;

CSVRow* parse_csv_row(const char* line);
void free_csv_row(CSVRow* row);

#endif
EOF

    cat << 'EOF' > /app/vendored/libstatscsv-1.0/statscsv.c
#include "statscsv.h"
#include <string.h>
/* Missing #include <stdlib.h> to cause implicit declaration error */

CSVRow* parse_csv_row(const char* line) {
    CSVRow* row = (CSVRow*)malloc(sizeof(CSVRow));
    row->count = 0;
    row->tokens = (char**)malloc(100 * sizeof(char*));
    char* copy = strdup(line);
    char* token = strtok(copy, ",");
    while (token != NULL) {
        row->tokens[row->count++] = strdup(token);
        token = strtok(NULL, ",");
    }
    free(copy);
    return row;
}

void free_csv_row(CSVRow* row) {
    for (int i = 0; i < row->count; i++) {
        free(row->tokens[i]);
    }
    free(row->tokens);
    free(row);
}
EOF

    cat << 'EOF' > /app/vendored/libstatscsv-1.0/Makefile
CC = gcc
CFLAGS = -Wall -Werror=implicit-function-declaration -fPIC

all: libstatscsv.a

libstatscsv.a: statscsv.o
	ar rcs $@ $^

statscsv.o: statscsv.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.a
EOF

    # Generate datasets using Python
    cat << 'EOF' > /tmp/gen_data.py
import os
import random

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# Generate clean data
for i in range(1, 6):
    with open(f'/app/corpus/clean/clean{i}.csv', 'w') as f:
        f.write("id,score\n")
        for j in range(100):
            score = int(random.gauss(50, 1))
            f.write(f"{j},{score}\n")

def write_evil(filename, scores):
    with open(f'/app/corpus/evil/{filename}', 'w') as f:
        f.write("id,score\n")
        for j, s in enumerate(scores):
            f.write(f"{j},{s}\n")

# Generate evil data
write_evil('evil1.csv', [int(random.gauss(50, 1)) if j != 50 else "NaN" for j in range(100)])
write_evil('evil2.csv', [int(random.gauss(50, 1)) if j != 50 else "N/A" for j in range(100)])
write_evil('evil3.csv', [int(random.gauss(50, 1)) if j != 50 else "" for j in range(100)])
write_evil('evil4.csv', [int(random.gauss(10, 1)) for j in range(100)])
write_evil('evil5.csv', [int(random.gauss(90, 1)) for j in range(100)])
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
