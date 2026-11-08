#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg imagemagick
    pip3 install pytest

    mkdir -p /app

    # Create the oracle program
    cat << 'EOF' > /app/oracle_filter.c
#include <stdio.h>
#include <stdint.h>

int main() {
    double mu = 0.0;
    double var = 100.0;
    double obs_var = 10.0;
    double x;

    while (fread(&x, sizeof(double), 1, stdin) == 1) {
        if (x == -999.0) {
            fwrite(&mu, sizeof(double), 1, stdout);
        } else {
            double prec_old = 1.0 / var;
            double prec_obs = 1.0 / obs_var;
            double prec_new = prec_old + prec_obs;
            mu = (prec_old * mu + prec_obs * x) / prec_new;
            var = 1.0 / prec_new;
            fwrite(&mu, sizeof(double), 1, stdout);
        }
    }
    return 0;
}
EOF
    gcc -O3 /app/oracle_filter.c -o /app/oracle_filter

    # Create the video fixture
    mkdir -p /tmp/frames
    for i in $(seq 1 100); do
        if [ $((i % 7)) -eq 0 ]; then
            convert -size 640x480 xc:black /tmp/frames/frame_$(printf "%03d" $i).png
        else
            val=$((50 + (i * 13) % 150))
            convert -size 640x480 xc:"gray($val)" /tmp/frames/frame_$(printf "%03d" $i).png
        fi
    done
    ffmpeg -y -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/stream.mp4
    rm -rf /tmp/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
