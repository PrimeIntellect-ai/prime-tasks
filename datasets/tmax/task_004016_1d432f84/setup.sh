#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest scipy numpy pandas

    mkdir -p /app/src
    mkdir -p /home/user

    cat << 'EOF' > /app/src/denoise.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[256];
    double t[1000], val[1000];
    int count = 0;

    if (fgets(line, sizeof(line), stdin) == NULL) return 0;
    printf("t,val\n");

    while (fgets(line, sizeof(line), stdin)) {
        if (sscanf(line, "%lf,%lf", &t[count], &val[count]) == 2) {
            count++;
        }
    }

    for (int i = 0; i < count; i++) {
        double sum = val[i];
        int n = 1;
        if (i > 0) { sum += val[i-1]; n++; }
        if (i < count - 1) { sum += val[i+1]; n++; }
        printf("%f,%f\n", t[i], sum / n);
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/sim_model.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    double alpha = atof(argv[1]);
    double beta = atof(argv[2]);
    double gamma = atof(argv[3]);

    printf("t,sim_val\n");
    for (int i = 0; i < 100; i++) {
        double t = (10.0 / 99.0) * i;
        double y = beta * exp(-alpha * t) * cos(gamma * t);
        printf("%f,%f\n", t, y);
    }
    return 0;
}
EOF

    gcc -o /app/sim_model /app/sim_model.c -lm
    strip -s /app/sim_model

    cat << 'EOF' > /tmp/generate_data.py
import json
import numpy as np

t = np.linspace(0, 10, 100)
true_y = 10.0 * np.exp(-0.5 * t) * np.cos(2.0 * t)

data = []
np.random.seed(42)
for i in range(100):
    sensors = (true_y[i] + np.random.normal(0, 2.0, 5)).tolist()
    data.append({"time": t[i], "sensors": sensors})

with open("/home/user/raw_data.json", "w") as f:
    json.dump(data, f)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
