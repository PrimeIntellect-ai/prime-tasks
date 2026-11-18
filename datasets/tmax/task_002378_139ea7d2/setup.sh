#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /home/user/sim_project
    cat << 'EOF' > /home/user/sim_project/spectrum_gen.c
#include <math.h>

void get_spectrum(int comp_id, double* out_array, int length) {
    double center = 0.0;
    if (comp_id == 0) center = 50.0;
    if (comp_id == 1) center = 100.0;
    if (comp_id == 2) center = 150.0;

    for (int i = 0; i < length; i++) {
        out_array[i] = exp(-pow((double)i - center, 2) / 200.0);
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
