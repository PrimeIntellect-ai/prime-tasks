#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /app/vendored/libcml-0.4.2
    mkdir -p /app/models
    mkdir -p /app/data

    # Create Makefile with bugs
    cat << 'EOF' > /app/vendored/libcml-0.4.2/Makefile
CC = gcc
CFLAGS = -O0 -g
LDFLAGS = 

all: libcml.so

libcml.so: cml.c
	$(CC) $(CFLAGS) -shared -fPIC -o $@ $< $(LDFLAGS)

clean:
	rm -f libcml.so
EOF

    # Create cml.h
    cat << 'EOF' > /app/vendored/libcml-0.4.2/cml.h
#ifndef CML_H
#define CML_H

typedef struct {
    int num_features;
    double *weights;
    double bias;
    double *mean;
    double *std;
} cml_model_t;

void cml_fit_transform_scale(double *batch_inputs, int n_items, int num_features);
void cml_transform_scale(cml_model_t *model, double *batch_inputs, int n_items);
void cml_predict_batch(cml_model_t *model, double *batch_inputs, int n_items, double *outputs);

#endif
EOF

    # Create cml.c with perturbation
    cat << 'EOF' > /app/vendored/libcml-0.4.2/cml.c
#include "cml.h"
#include <stdlib.h>
#include <math.h>

void cml_fit_transform_scale(double *batch_inputs, int n_items, int num_features) {
    // Dummy implementation
}

void cml_transform_scale(cml_model_t *model, double *batch_inputs, int n_items) {
    // Dummy implementation
}

void cml_predict_batch(cml_model_t *model, double *batch_inputs, int n_items, double *outputs) {
    // PERTURBATION: Calls fit_transform on test data, leaking batch statistics
    cml_fit_transform_scale(batch_inputs, n_items, model->num_features); 

    for(int i = 0; i < n_items; i++) {
        outputs[i] = 0.0;
    }
}
EOF

    # Create dummy models
    echo "dummy model A" > /app/models/model_A.bin
    echo "dummy model B" > /app/models/model_B.bin
    echo "dummy model C" > /app/models/model_C.bin

    # Create val.csv
    for i in $(seq 1 100); do
        echo "0.1,0.2,0.3,0.4,1.0" >> /app/data/val.csv
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
