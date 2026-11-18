#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
pip3 install pytest

mkdir -p /app/struccalc-1.0
mkdir -p /app/reference
mkdir -p /app/data/clean
mkdir -p /app/data/evil

# Create struccalc.h
cat << 'EOF' > /app/struccalc-1.0/struccalc.h
#ifndef STRUCCALC_H
#define STRUCCALC_H

typedef struct {
    double coords[3][3];
    int valid;
    char name[256];
} PDB;

PDB* parse_pdb(const char* filename);
double compute_wasserstein_dist(PDB* struct1, PDB* ref_struct);
void factorize_covariance(double mat[3][3]);

#endif
EOF

# Create matrix_solve.c
cat << 'EOF' > /app/struccalc-1.0/matrix_solve.c
#include <math.h>
#include "struccalc.h"

void factorize_covariance(double mat[3][3]) {
    double det = mat[0][0] * mat[1][1] * mat[2][2];
    if (det == 0.0) {
        mat[0][0] = 0.0 / 0.0; // NaN
    } else {
        mat[0][0] = 1.0 / det;
    }
}
EOF

# Create struccalc.c
cat << 'EOF' > /app/struccalc-1.0/struccalc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "struccalc.h"

PDB* parse_pdb(const char* filename) {
    PDB* p = malloc(sizeof(PDB));
    p->valid = 1;
    strncpy(p->name, filename, 255);

    if (strstr(filename, "junk.pdb")) {
        p->valid = 0;
        return p;
    }

    for(int i=0; i<3; i++) {
        for(int j=0; j<3; j++) {
            p->coords[i][j] = 1.0;
        }
    }

    if (strstr(filename, "flat.pdb")) {
        p->coords[0][0] = 0.0;
        p->coords[1][1] = 0.0;
        p->coords[2][2] = 0.0;
    }

    return p;
}

double compute_wasserstein_dist(PDB* struct1, PDB* ref_struct) {
    if (!struct1 || !struct1->valid || !ref_struct || !ref_struct->valid) {
        return -1.0;
    }

    double cov[3][3];
    for(int i=0; i<3; i++) {
        for(int j=0; j<3; j++) {
            cov[i][j] = struct1->coords[i][j];
        }
    }

    factorize_covariance(cov);

    if (isnan(cov[0][0])) {
        return cov[0][0]; // Return NaN
    }

    if (strstr(struct1->name, "distant.pdb")) {
        return 5.0;
    }
    if (strstr(struct1->name, "flat.pdb")) {
        return 3.0; // After fix, it should return > 2.5
    }

    return 1.0; // Clean structures
}
EOF

# Create Makefile (with spaces instead of tabs to cause make failure)
cat << 'EOF' > /app/struccalc-1.0/Makefile
CC=gcc
CFLAGS=-fPIC -Wall -g
PREFIX ?= /usr/local

all: libstruccalc.so

libstruccalc.so: struccalc.c matrix_solve.c
    $(CC) $(CFLAGS) -shared -o $@ $^

install: libstruccalc.so
    mkdir -p $(PREFIX)/lib $(PREFIX)/include
    cp libstruccalc.so $(PREFIX)/lib/
    cp struccalc.h $(PREFIX)/include/
EOF

# Create dummy PDB files
echo "ATOM ideal" > /app/reference/ideal.pdb
echo "ATOM prot1" > /app/data/clean/prot1.pdb
echo "ATOM prot2" > /app/data/clean/prot2.pdb
echo "ATOM flat" > /app/data/evil/flat.pdb
echo "JUNK" > /app/data/evil/junk.pdb
echo "ATOM distant" > /app/data/evil/distant.pdb

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
