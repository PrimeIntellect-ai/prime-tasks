#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make build-essential
    pip3 install pytest

    mkdir -p /app/fastcovar-0.3/include
    mkdir -p /app/fastcovar-0.3/src
    mkdir -p /app/fastcovar-0.3/lib

    cat << 'EOF' > /app/fastcovar-0.3/include/fastcovar.h
#ifndef FASTCOVAR_H
#define FASTCOVAR_H

typedef double scalar_t;

void compute_pearson_3x3(double* col1, double* col2, double* col3, int n, double out_matrix[3][3]);

#endif
EOF

    cat << 'EOF' > /app/fastcovar-0.3/src/fastcovar.c
#include "fastcovar.h"
#include <math.h>

void compute_pearson_3x3(double* col1, double* col2, double* col3, int n, double out_matrix[3][3]) {
    double* cols[3] = {col1, col2, col3};
    double means[3] = {0};
    for(int j=0; j<3; j++) {
        scalar_t sum = 0;
        for(int i=0; i<n; i++) sum += cols[j][i];
        means[j] = (double)sum / n;
    }
    for(int j=0; j<3; j++) {
        for(int k=0; k<3; k++) {
            scalar_t num = 0;
            scalar_t den1 = 0;
            scalar_t den2 = 0;
            for(int i=0; i<n; i++) {
                num += (cols[j][i] - means[j]) * (cols[k][i] - means[k]);
                den1 += (cols[j][i] - means[j]) * (cols[j][i] - means[j]);
                den2 += (cols[k][i] - means[k]) * (cols[k][i] - means[k]);
            }
            if (den1 == 0 || den2 == 0) out_matrix[j][k] = 0;
            else out_matrix[j][k] = (double)num / sqrt((double)den1 * (double)den2);
        }
    }
}
EOF

    cat << 'EOF' > /app/fastcovar-0.3/Makefile
CC=gcc
CFLAGS=-O2 -Iinclude

all: lib/libfastcovar.a

lib/libfastcovar.a: src/fastcovar.o
	mkdir -p lib
	ar rcs $@ $^

src/fastcovar.o: src/fastcovar.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf lib src/*.o
EOF

    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "fastcovar.h"

#define MAX_ROWS 100000

double col1[MAX_ROWS];
double col2[MAX_ROWS];
double col3[MAX_ROWS];

int main() {
    char line[1024];
    int valid = 0;
    int dropped = 0;
    while(fgets(line, sizeof(line), stdin)) {
        if(strstr(line, "NaN")) { dropped++; continue; }
        double v1, v2, v3;
        if(sscanf(line, "%lf,%lf,%lf", &v1, &v2, &v3) != 3) { dropped++; continue; }
        if(v1 < -1000.0 || v1 > 1000.0 || v2 < -1000.0 || v2 > 1000.0 || v3 < -1000.0 || v3 > 1000.0) { dropped++; continue; }
        col1[valid] = v1;
        col2[valid] = v2;
        col3[valid] = v3;
        valid++;
    }
    fprintf(stderr, "Valid rows: %d, Dropped rows: %d\n", valid, dropped);
    if(valid > 0) {
        double out[3][3];
        compute_pearson_3x3(col1, col2, col3, valid, out);
        for(int i=0; i<3; i++) {
            printf("%.4f,%.4f,%.4f\n", out[i][0], out[i][1], out[i][2]);
        }
    }
    return 0;
}
EOF

    # Build the fixed library
    cd /app/fastcovar-0.3
    make

    # Compile the oracle
    cd /app
    gcc -O2 oracle.c -I/app/fastcovar-0.3/include -L/app/fastcovar-0.3/lib -lfastcovar -lm -static -o oracle_correlate
    strip oracle_correlate
    rm oracle.c

    # Clean up the library build
    cd /app/fastcovar-0.3
    make clean

    # Reintroduce the bug
    sed -i 's/typedef double scalar_t;/typedef int scalar_t;/g' /app/fastcovar-0.3/include/fastcovar.h

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/fastcovar-0.3
