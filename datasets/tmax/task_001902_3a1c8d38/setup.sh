#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        tesseract-ocr \
        gcc \
        fonts-dejavu-core

    pip3 install pytest numpy scipy Pillow pytesseract

    mkdir -p /app

    # Generate image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -gravity center -draw "text 0,0 'TARGET SPECTRUM: Peak at f0 = 4.25 Hz, Gamma = 0.15'" \
        /app/reference_spectrum.png

    # Create buggy simulator.c
    cat << 'EOF' > /app/simulator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char** argv) {
    if (argc < 4) return 1;
    double f0 = atof(argv[1]);
    double gamma = atof(argv[2]);
    int seed = atoi(argv[3]);
    srand(seed);

    // BUG: Time step is too large, causing instability and aliasing
    double dt = 0.2; 
    int steps = 1000; // Total time = 200s

    double x = 1.0;
    double v = 0.0;
    double w2 = 4.0 * M_PI * M_PI * f0 * f0;

    for (int i=0; i<steps; i++) {
        double noise = ((double)rand() / RAND_MAX - 0.5) * 2.0;
        double a = -2.0 * gamma * v - w2 * x + noise;
        v += a * dt;
        x += v * dt;
        printf("%f\n", x);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
