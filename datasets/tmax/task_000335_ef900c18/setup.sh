#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make socat ncat
    pip3 install pytest

    mkdir -p /app/artifact_pca

    cat << 'EOF' > /app/artifact_pca/pca.h
#ifndef PCA_H
#define PCA_H
void project_4d_to_2d(float f1, float f2, float f3, float f4, float *out1, float *out2);
#endif
EOF

    cat << 'EOF' > /app/artifact_pca/pca.c
#include "pca.h"
#include <math.h>

void project_4d_to_2d(float f1, float f2, float f3, float f4, float *out1, float *out2) {
    // Use a math function to require -lm
    float dummy = sqrt(1.0f);
    *out1 = f1 + f2 + dummy - 1.0f;
    *out2 = f3 + f4;
}
EOF

    cat << 'EOF' > /app/artifact_pca/reducer.c
#include <stdio.h>
#include "pca.h"

int main() {
    float f1, f2, f3, f4;
    // Bug: using %d instead of %f
    if (scanf("EMBEDDING:%d,%d,%d,%d", &f1, &f2, &f3, &f4) != 4) {
        printf("ERROR: Invalid input format\n");
        return 1;
    }
    float out1, out2;
    project_4d_to_2d(f1, f2, f3, f4, &out1, &out2);
    printf("PROJECTION:%.2f,%.2f\n", out1, out2);
    return 0;
}
EOF

    cat << 'EOF' > /app/artifact_pca/Makefile
all: reducer

reducer: reducer.o pca.o
	gcc -o reducer reducer.o pca.o

reducer.o: reducer.c
	gcc -c reducer.c

pca.o: pca.c
	gcc -c pca.c

clean:
	rm -f *.o reducer
EOF

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
