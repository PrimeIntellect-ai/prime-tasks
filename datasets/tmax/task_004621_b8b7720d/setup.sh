#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        fonts-dejavu-core \
        gcc

    pip3 install pytest Pillow

    mkdir -p /app

    # Generate the oracle binary
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    double t_end = atof(argv[1]);
    int num_steps = atoi(argv[2]);

    double alpha = 0.8, beta = 0.2, delta = 0.1, gamma = 0.4;
    double x = 40.0, y = 20.0;

    double dt = t_end / num_steps;
    for (int i = 0; i < num_steps; i++) {
        double k1_x = alpha*x - beta*x*y;
        double k1_y = delta*x*y - gamma*y;

        double x2 = x + 0.5*dt*k1_x;
        double y2 = y + 0.5*dt*k1_y;
        double k2_x = alpha*x2 - beta*x2*y2;
        double k2_y = delta*x2*y2 - gamma*y2;

        double x3 = x + 0.5*dt*k2_x;
        double y3 = y + 0.5*dt*k2_y;
        double k3_x = alpha*x3 - beta*x3*y3;
        double k3_y = delta*x3*y3 - gamma*y3;

        double x4 = x + dt*k3_x;
        double y4 = y + dt*k3_y;
        double k4_x = alpha*x4 - beta*x4*y4;
        double k4_y = delta*x4*y4 - gamma*y4;

        x = x + (dt/6.0)*(k1_x + 2*k2_x + 2*k3_x + k4_x);
        y = y + (dt/6.0)*(k1_y + 2*k2_y + 2*k3_y + k4_y);
    }

    printf("%.4f %.4f\n", x, y);
    return 0;
}
EOF
    gcc -O3 /app/oracle.c -o /app/oracle_integrator
    rm /app/oracle.c
    chmod +x /app/oracle_integrator

    # Generate the parameter image
    cat << 'EOF' > /app/make_image.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
text = "Lotka-Volterra Run 7\nalpha=0.8\nbeta=0.2\ndelta=0.1\ngamma=0.4\nx0=40.0\ny0=20.0"
d.text((20, 20), text, font=font, fill=(0, 0, 0))
img.save('/app/model_params.png')
EOF
    python3 /app/make_image.py
    rm /app/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
