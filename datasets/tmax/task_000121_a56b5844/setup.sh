#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc
    pip3 install pytest numpy pandas scipy

    mkdir -p /app
    cat << 'EOF' > /app/q_oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    double x = atof(argv[1]);
    double y = atof(argv[2]);
    double q = 0.5 * y * y + 1.5 * x * x * x * x - 2.0 * x * x;
    printf("%f\n", q);
    return 0;
}
EOF
    gcc -O3 -o /app/q_oracle /app/q_oracle.c
    strip /app/q_oracle
    rm /app/q_oracle.c

    mkdir -p /home/user/samples
    mkdir -p /verify/corpus/clean
    mkdir -p /verify/corpus/evil

    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import pandas as pd
from scipy.integrate import odeint
import os

def generate_clean(filename, x0, y0):
    t = np.linspace(0, 10, 100)
    def deriv(state, t):
        x, y = state
        return [y, 4.0*x - 6.0*x**3]
    state = odeint(deriv, [x0, y0], t)
    df = pd.DataFrame({'t': t, 'x': state[:,0], 'y': state[:,1]})
    df.to_csv(filename, index=False)

def generate_evil_kinematic(filename):
    t = np.linspace(0, 10, 100)
    x = np.sin(t)
    y = np.cos(t) + 0.2  # breaks kinematic
    df = pd.DataFrame({'t': t, 'x': x, 'y': y})
    df.to_csv(filename, index=False)

def generate_evil_conservation(filename, x0, y0):
    t = np.linspace(0, 10, 100)
    def deriv(state, t):
        x, y = state
        return [y, 4.0*x - 6.0*x**3 - 0.2*y]  # dampening
    state = odeint(deriv, [x0, y0], t)
    df = pd.DataFrame({'t': t, 'x': state[:,0], 'y': state[:,1]})
    df.to_csv(filename, index=False)

generate_clean('/home/user/samples/clean_sample.csv', 1.0, 0.0)
generate_evil_kinematic('/home/user/samples/evil_sample.csv')

for i in range(5):
    generate_clean(f'/verify/corpus/clean/clean_{i}.csv', 1.0 + i*0.05, 0.0)
    generate_evil_kinematic(f'/verify/corpus/evil/evil_k_{i}.csv')
    generate_evil_conservation(f'/verify/corpus/evil/evil_c_{i}.csv', 1.5, 0.0)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /verify
