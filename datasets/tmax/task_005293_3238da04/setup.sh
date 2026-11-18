#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/integrator.cpp
#include <cmath>
#include <algorithm>

extern "C" {
    double f(double t, double y, double lambda) {
        return -lambda * y;
    }

    int integrate(double y0, double t_end, double lambda, double tol, double* y_out, int* steps_out) {
        double t = 0.0;
        double y = y0;
        double h = 0.1;
        int steps = 0;
        int max_steps = 100000;

        while (t < t_end && steps < max_steps) {
            double k1 = f(t, y, lambda);
            double k2 = f(t + h, y + h * k1, lambda);

            double y_new = y + h / 2.0 * (k1 + k2);
            double error = std::abs(h / 2.0 * (k2 - k1));

            if (error == 0.0) error = 1e-15;

            if (error <= tol) {
                t += h;
                y = y_new;
            }

            // BUG: Inverted ratio for step-size adaptation
            h = h * 0.9 * std::sqrt(error / tol);

            h = std::max(1e-5, std::min(h, 0.5));
            if (t + h > t_end) h = t_end - t;

            steps++;
        }

        *y_out = y;
        *steps_out = steps;
        return (steps >= max_steps) ? -1 : 0;
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
