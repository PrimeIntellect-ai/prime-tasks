#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        imagemagick \
        fonts-dejavu-core \
        tesseract-ocr \
        gcc \
        libc6-dev

    pip3 install pytest numpy flask fastapi uvicorn pytesseract scipy scikit-learn

    mkdir -p /app
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,50 'Simulation parameters: alpha=3.14 beta=2.71'" /app/config.png

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sim.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    double alpha = atof(argv[1]);
    double beta = atof(argv[2]);

    // Deterministic pseudo-random generation
    srand(42);
    for(int i=0; i<100; i++) {
        double x = i * 0.1;
        double noise = ((double)rand() / RAND_MAX - 0.5) * 2.0;
        double y = alpha * x + beta + noise;
        printf("%f %f\n", x, y);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
