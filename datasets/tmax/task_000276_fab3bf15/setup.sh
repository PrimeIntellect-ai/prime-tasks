#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy scikit-learn

    # Create the C code generator
    cat << 'EOF' > /tmp/gen.py
import os
import numpy as np

os.makedirs('/app', exist_ok=True)
np.random.seed(42)
W_true = np.random.randn(50, 5)
b_true = np.random.randn(5)

with open('/tmp/extractor.c', 'w') as f:
    f.write("#include <stdio.h>\n")
    f.write("#include <stdlib.h>\n")
    f.write("#include <string.h>\n")
    f.write("#include <math.h>\n")
    f.write("double W[50][5] = {\n")
    for i in range(50):
        f.write("    {" + ", ".join(map(str, W_true[i])) + "},\n")
    f.write("};\n")
    f.write("double b[5] = {" + ", ".join(map(str, b_true)) + "};\n")
    f.write("""
double randn_noise() {
    double u1 = ((double) rand() / (RAND_MAX));
    double u2 = ((double) rand() / (RAND_MAX));
    if (u1 == 0.0) u1 = 1e-10;
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

int main() {
    char line[8192];
    while (fgets(line, sizeof(line), stdin)) {
        double x[50];
        char *tok = strtok(line, ",");
        int i = 0;
        while (tok && i < 50) {
            x[i++] = atof(tok);
            tok = strtok(NULL, ",");
        }
        if (i < 50) continue;

        double y[5];
        for (int j = 0; j < 5; j++) {
            y[j] = b[j];
            for (int k = 0; k < 50; k++) {
                y[j] += x[k] * W[k][j];
            }
            y[j] += randn_noise() * 0.1;
        }
        printf("%f,%f,%f,%f,%f\\n", y[0], y[1], y[2], y[3], y[4]);
    }
    return 0;
}
""")
EOF

    # Generate, compile, and strip the binary
    python3 /tmp/gen.py
    gcc -O3 /tmp/extractor.c -o /app/feature_extractor -lm
    strip /app/feature_extractor

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
