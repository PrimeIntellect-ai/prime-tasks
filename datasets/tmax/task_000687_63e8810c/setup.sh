#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential curl
    pip3 install pytest

    mkdir -p /app/tinycsv-1.0

    cat << 'EOF' > /app/tinycsv-1.0/Makefile
CC=not-a-real-compiler
CFLAGS=-Wall -fPIC

all: libtinycsv.so libtinycsv.a

libtinycsv.so: tinycsv.o
	$(CC) -shared -o $@ $^

libtinycsv.a: tinycsv.o
	ar rcs $@ $^

tinycsv.o: tinycsv.c
	$(CC) $(CFLAGS) -c $<

clean:
	rm -f *.o *.so *.a
EOF

    cat << 'EOF' > /app/tinycsv-1.0/tinycsv.h
#ifndef TINYCSV_H
#define TINYCSV_H

int parse_csv_line(const char *line, char ***fields, int *num_fields);
void free_csv_line(char **fields, int num_fields);

#endif
EOF

    cat << 'EOF' > /app/tinycsv-1.0/tinycsv.c
#include "tinycsv.h"
#include <stdlib.h>
#include <string.h>

int parse_csv_line(const char *line, char ***fields, int *num_fields) {
    int count = 0;
    const char *p = line;

    while (*p) {
        if (*p == ',') count++;
        p++;
    }

    *num_fields = count + 1;
    *fields = malloc(sizeof(char*) * (*num_fields));
    if (!*fields) return -1;

    p = line;
    for (int i = 0; i < *num_fields; i++) {
        const char *start = p;
        while (*p && *p != ',' && *p != '\n' && *p != '\r') {
            char current_char = *p;
            char next_char = *(p+1);
            if (current_char == '\\' && next_char == 'u') {
                return -1; // PARSE ERROR
            }
            p++;
        }
        int len = p - start;
        (*fields)[i] = malloc(len + 1);
        strncpy((*fields)[i], start, len);
        (*fields)[i][len] = '\0';
        if (*p == ',') p++;
    }

    return 0;
}

void free_csv_line(char **fields, int num_fields) {
    if (!fields) return;
    for (int i = 0; i < num_fields; i++) {
        free(fields[i]);
    }
    free(fields);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/tinycsv-1.0
