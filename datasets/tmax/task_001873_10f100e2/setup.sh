#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create vendored library directory
    mkdir -p /app/vendored/simple_csv_parser

    # Create csv_parser.h
    cat << 'EOF' > /app/vendored/simple_csv_parser/csv_parser.h
#ifndef CSV_PARSER_H
#define CSV_PARSER_H

typedef struct {
    char ***rows;
    int num_rows;
    int num_cols;
} CSVData;

CSVData* parse_csv(const char* filename);
void free_csv(CSVData* data);

#endif
EOF

    # Create csv_parser.c
    cat << 'EOF' > /app/vendored/simple_csv_parser/csv_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "csv_parser.h"

CSVData* parse_csv(const char* filename) {
    FILE *f = fopen(filename, "r");
    if (!f) return NULL;
    CSVData *data = malloc(sizeof(CSVData));
    data->num_rows = 0;
    data->num_cols = 2;
    data->rows = malloc(100 * sizeof(char**));
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\r\n")] = 0;
        char **row = malloc(2 * sizeof(char*));
        char *tok = strtok(line, ",");
        row[0] = tok ? strdup(tok) : strdup("");
        tok = strtok(NULL, ",");
        row[1] = tok ? strdup(tok) : strdup("");
        data->rows[data->num_rows++] = row;
    }
    fclose(f);
    return data;
}

void free_csv(CSVData* data) {
    if (!data) return;
    for (int i=0; i<data->num_rows; i++) {
        free(data->rows[i][0]);
        free(data->rows[i][1]);
        free(data->rows[i]);
    }
    free(data->rows);
    free(data);
}
EOF

    # Create Makefile with perturbation
    cat << 'EOF' > /app/vendored/simple_csv_parser/Makefile
CC=invalid_compiler
CFLAGS=-Wall -Wextra -fPIC

all: libcsv_parser.a

libcsv_parser.a: csv_parser.o
	ar rcs $@ $^

csv_parser.o: csv_parser.c csv_parser.h
	$(CC) $(CFLAGS) -c csv_parser.c -o csv_parser.o

clean:
	rm -f *.o *.a
EOF

    # Create nodes.csv
    cat << 'EOF' > /home/user/nodes.csv
id,name
A,Root
B,Child 1
C,Child 2
D,Grandchild 1
EOF

    # Create edges.csv
    cat << 'EOF' > /home/user/edges.csv
parent_id,child_id
A,B
A,C
B,D
EOF

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
