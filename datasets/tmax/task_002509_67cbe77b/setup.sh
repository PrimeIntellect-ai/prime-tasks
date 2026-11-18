#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc imagemagick
    pip3 install pytest numpy scipy flask

    mkdir -p /app
    convert -size 400x200 xc:white -fill black -pointsize 24 -draw "text 50,100 'Damping: 0.15\nFreq: 2.5Hz'" /app/system_specs.png

    mkdir -p /home/user
    cat << 'EOF' > /home/user/integrator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    double duration = 10.0;
    if (argc > 1) duration = atof(argv[1]);

    char* damp_str = getenv("DAMPING_COEF");
    char* freq_str = getenv("NATURAL_FREQ");

    double zeta = damp_str ? atof(damp_str) : 0.0;
    double omega0 = freq_str ? atof(freq_str) : 1.0;

    double dt = 0.01;
    for (double t = 0; t <= duration; t += dt) {
        double val = exp(-zeta * omega0 * t) * cos(omega0 * t);
        printf("%f %f\n", t, val);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
