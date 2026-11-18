#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pandas numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
int main() {
    double t = 0.0, x = 2.0, v = 0.0;
    double dt = 0.01;
    double omega = 1.5, gamma = 0.2, alpha = 0.1;
    printf("Starting legacy simulation...\n");
    for(int i=0; i<=2000; i++) {
        printf("Time: %.4f | Position: %.6f | Velocity: %.6f\n", t, x, v);

        double k1_x = v;
        double k1_v = -gamma*v - omega*omega*x - alpha*x*x*x;

        double x2 = x + 0.5*dt*k1_x;
        double v2 = v + 0.5*dt*k1_v;
        double k2_x = v2;
        double k2_v = -gamma*v2 - omega*omega*x2 - alpha*x2*x2*x2;

        double x3 = x + 0.5*dt*k2_x;
        double v3 = v + 0.5*dt*k2_v;
        double k3_x = v3;
        double k3_v = -gamma*v3 - omega*omega*x3 - alpha*x3*x3*x3;

        double x4 = x + dt*k3_x;
        double v4 = v + dt*k3_v;
        double k4_x = v4;
        double k4_v = -gamma*v4 - omega*omega*x4 - alpha*x4*x4*x4;

        x = x + (dt/6.0)*(k1_x + 2*k2_x + 2*k3_x + k4_x);
        v = v + (dt/6.0)*(k1_v + 2*k2_v + 2*k3_v + k4_v);
        t += dt;
    }
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/oracle_sim
    strip /app/oracle_sim
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
