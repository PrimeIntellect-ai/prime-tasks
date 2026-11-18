#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest matplotlib numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    char *str1 = strdup(argv[1]);
    char *str2 = strdup(argv[2]);

    double sum = 0.0;
    int count = 0;

    char *tok1 = strtok(str1, ",");
    char *tok2 = strtok(str2, ",");

    while (tok1 != NULL && tok2 != NULL) {
        double a = atof(tok1);
        double p = atof(tok2);

        double diff = log(p + 1.0) - log(a + 1.0);
        sum += diff * diff;
        count++;

        tok1 = strtok(NULL, ",");
        tok2 = strtok(NULL, ",");
    }

    if (count == 0) return 1;

    double rmsle = sqrt(sum / count);
    printf("%.4f\n", rmsle);

    free(str1);
    free(str2);
    return 0;
}
EOF
    gcc -O2 -s -o /app/drift_oracle /tmp/oracle.c -lm
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/plot_experiments.py
import matplotlib.pyplot as plt
import numpy as np

epochs = np.arange(1, 11)
loss = [2.5, 2.0, 1.6, 1.4, 1.2, 1.0, 0.9, 0.8, 0.75, 0.7]

plt.plot(epochs, loss, marker='o')
plt.title('Training Loss')
plt.xlabel('Epoch')
plt.ylabel('Loss')

plt.show()
plt.savefig('/home/user/experiment_plot.png')
EOF

    chmod -R 777 /home/user
