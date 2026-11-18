#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import csv

def rk4_step(x, y, alpha, beta, gamma, delta, dt):
    dx1 = alpha * x - beta * x * y
    dy1 = delta * x * y - gamma * y

    x2 = x + 0.5 * dt * dx1
    y2 = y + 0.5 * dt * dy1
    dx2 = alpha * x2 - beta * x2 * y2
    dy2 = delta * x2 * y2 - gamma * y2

    x3 = x + 0.5 * dt * dx2
    y3 = y + 0.5 * dt * dy2
    dx3 = alpha * x3 - beta * x3 * y3
    dy3 = delta * x3 * y3 - gamma * y3

    x4 = x + dt * dx3
    y4 = y + dt * dy3
    dx4 = alpha * x4 - beta * x4 * y4
    dy4 = delta * x4 * y4 - gamma * y4

    x_new = x + (dt / 6.0) * (dx1 + 2*dx2 + 2*dx3 + dx4)
    y_new = y + (dt / 6.0) * (dy1 + 2*dy2 + 2*dy3 + dy4)
    return x_new, y_new

alpha, beta, gamma, delta = 1.5, 1.0, 3.0, 1.0
dt = 0.1
t_max = 50.0

x, y = 40.0, 9.0
t = 0.0

with open('/home/user/reference_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['t', 'x', 'y'])
    writer.writerow([round(t, 1), x, y])

    for _ in range(500):
        x, y = rk4_step(x, y, alpha, beta, gamma, delta, dt)
        t += dt
        writer.writerow([round(t, 1), x, y])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
