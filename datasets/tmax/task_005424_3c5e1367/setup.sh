#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pandas numpy matplotlib scikit-learn

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    double a = atof(argv[1]);
    double b = atof(argv[2]);
    double res = sin(a) * 2.0 + cos(b) * 3.0 + a*b;
    printf("%f\n", res);
    return 0;
}
EOF
    gcc -O3 /tmp/oracle.c -o /app/oracle_bin -lm
    strip /app/oracle_bin
    chmod +x /app/oracle_bin

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

def gen_data(n_samples, filename):
    ids = np.arange(n_samples)
    fA = np.random.uniform(-5, 5, n_samples)
    fB = np.random.uniform(-5, 5, n_samples)
    fC = np.random.normal(0, 1, n_samples)
    df = pd.DataFrame({'id': ids, 'featureA': fA, 'featureB': fB, 'featureC': fC})
    df.to_csv(filename, index=False)

gen_data(2000, '/home/user/train.csv')
gen_data(500, '/home/user/test.csv')
EOF
    python3 /tmp/gen_data.py

    cat << 'EOF' > /home/user/plot_data.py
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv('/home/user/train.csv')
plt.hist(df['featureC'], bins=20)
plt.show() # Causes the figure to be cleared before savefig
plt.savefig('/home/user/plot.png')
EOF

    chmod -R 777 /home/user
