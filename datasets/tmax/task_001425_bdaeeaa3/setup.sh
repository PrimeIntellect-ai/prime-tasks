#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        libsm6 \
        libxext6 \
        g++ \
        make \
        wget

    pip3 install pytest numpy scipy opencv-python-headless flask requests

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/sim_project

    # Generate the video
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

width, height = 640, 480
fps = 30
duration = 10
frames = fps * duration

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/pendulum_experiment.mp4', fourcc, fps, (width, height))

c = 0.30
k = 9.81
omega = np.sqrt(k - (c/2)**2)

for i in range(frames):
    t = i / fps
    x = np.exp(-c * t / 2) * np.cos(omega * t)

    img = np.ones((height, width, 3), dtype=np.uint8) * 255

    px = int(320 + x * 220)
    py = 240

    cv2.circle(img, (px, py), 20, (0, 0, 255), -1)
    out.write(img)

out.release()
EOF
    python3 /tmp/generate_video.py

    # Create C++ files
    cat << 'EOF' > /home/user/sim_project/main.cpp
#include <iostream>
#include <vector>
#include <cstdlib>

extern void integrate(double c, double k, double t_end, double dt, std::vector<double>& t_out, std::vector<double>& x_out);

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <c>\n";
        return 1;
    }
    double c = std::atof(argv[1]);
    double k = 9.81;
    std::vector<double> t_out, x_out;
    integrate(c, k, 10.0, 1.0/30.0, t_out, x_out);
    for (size_t i = 0; i < t_out.size(); ++i) {
        std::cout << t_out[i] << " " << x_out[i] << "\n";
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/sim_project/integrator.cpp
#include <vector>
#include <cmath>

void integrate(double c, double k, double t_end, double dt_target, std::vector<double>& t_out, std::vector<double>& x_out) {
    double t = 0;
    double x = 1.0;
    double v = 0.0;
    double step_size = 0.01;
    double tolerance = 1e-6;

    while (t <= t_end) {
        t_out.push_back(t);
        x_out.push_back(x);

        double y_rk4 = x + v * step_size;
        double y_rk5 = x + v * step_size + 1e-5;

        double error = std::abs(y_rk5 - y_rk4); 
        if (error < tolerance) { 
            step_size *= 2.0; 
        } else { 
            step_size *= 2.0; 
        }

        t += step_size;
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
