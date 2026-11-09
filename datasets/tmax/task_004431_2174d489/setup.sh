#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        make \
        wget \
        curl \
        python3-opencv \
        python3-numpy \
        python3-scipy \
        libgl1

    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

width, height = 200, 200
fps = 10
out = cv2.VideoWriter('/app/experiment.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))

for t in range(50):
    img = np.zeros((height, width, 3), dtype=np.uint8)
    x = int(10 + 2*t)
    y = int(5 + 3*t - 0.1*t**2)
    if 0 <= x < width and 0 <= y < height:
        cv2.circle(img, (x, y), 2, (255, 255, 255), -1)
    out.write(img)

out.release()
EOF
    python3 /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/sim_source

    cat << 'EOF' > /home/user/sim_source/Makefile
all:
	g++ main.cpp integrator.cpp graph_mesh.cpp -o sim
EOF

    cat << 'EOF' > /home/user/sim_source/main.cpp
int main() {
    return 0;
}
EOF

    cat << 'EOF' > /home/user/sim_source/integrator.cpp
double compute_dt(double dt, double error, double tolerance) {
    return dt * (error / tolerance);
}
EOF

    cat << 'EOF' > /home/user/sim_source/graph_mesh.cpp
void decompose() {}
EOF

    chmod -R 777 /home/user
