#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget tar
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Download liblbfgs from Debian sources
    wget http://deb.debian.org/debian/pool/main/libl/liblbfgs/liblbfgs_1.10.orig.tar.gz -O liblbfgs-1.10.tar.gz
    tar -xzf liblbfgs-1.10.tar.gz

    # Apply perturbations
    sed -i 's/#include <math.h>//g' /app/liblbfgs-1.10/lib/lbfgs.c
    echo 'CFLAGS += -Wall -O0 -Werror=implicit-function-declaration' >> /app/liblbfgs-1.10/Makefile.in

    mkdir -p /app/project

    cat << 'EOF' > /app/project/main.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <lbfgs.h>

static lbfgsfloatval_t evaluate(
    void *instance,
    const lbfgsfloatval_t *x,
    lbfgsfloatval_t *g,
    const int n,
    const lbfgsfloatval_t step
    )
{
    lbfgsfloatval_t fx = 0.0;

    // Rosenbrock function: f(x,y) = (1-x)^2 + 100(y-x^2)^2
    lbfgsfloatval_t t1 = 1.0 - x[0];
    lbfgsfloatval_t t2 = 10.0 * (x[1] - x[0] * x[0]);

    g[0] = -2.0 * t1 + 400.0 * x[0] * (x[1] - x[0] * x[0]); // Deliberate typo: + 400 instead of - 400
    g[1] = 200.0 * (x[1] - x[0] * x[0]);

    fx = t1 * t1 + t2 * t2;
    return fx;
}

static int progress(
    void *instance,
    const lbfgsfloatval_t *x,
    const lbfgsfloatval_t *g,
    const lbfgsfloatval_t fx,
    const lbfgsfloatval_t xnorm,
    const lbfgsfloatval_t gnorm,
    const lbfgsfloatval_t step,
    int n,
    int k,
    int ls
    )
{
    return 0;
}

int main(int argc, char *argv[])
{
    int i, ret = 0;
    lbfgsfloatval_t fx;
    lbfgsfloatval_t *x = lbfgs_malloc(2);

    if (x == NULL) {
        printf("ERROR: Failed to allocate a memory block for variables.\n");
        return 1;
    }

    FILE *fp = fopen("sensor_data.csv", "r");
    if (fp) {
        float val1, val2;
        if (fscanf(fp, "%f,%f", &val1, &val2) == 2) {
            x[0] = val1;
            x[1] = val2;
        } else {
            x[0] = -1.2;
            x[1] = 1.0;
        }
        fclose(fp);
    } else {
        x[0] = -1.2;
        x[1] = 1.0;
    }

    // Missing NaN/Inf check here

    ret = lbfgs(2, x, &fx, evaluate, progress, NULL, NULL);

    FILE *out = fopen("result.txt", "w");
    if (out) {
        fprintf(out, "Final cost: %f\n", fx);
        fclose(out);
    }

    lbfgs_free(x);
    return 0;
}
EOF

    cat << 'EOF' > /app/project/sensor_data.csv
NaN,inf
EOF

    cat << 'EOF' > /app/project/Makefile
CC = gcc
CFLAGS = -I/app/local/include -Wall -O2
LDFLAGS = -L/app/local/lib -llbfgs -lm

all: optimize_sensor

optimize_sensor: main.c
	$(CC) $(CFLAGS) -o optimize_sensor main.c $(LDFLAGS)

clean:
	rm -f optimize_sensor result.txt
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user /app
