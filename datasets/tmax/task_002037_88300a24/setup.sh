#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest fastapi uvicorn httpx packaging

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src
    mkdir -p /home/user/libs

    cat << 'EOF' > /home/user/src/mathops_v1.c
#include <math.h>
double calculate_trajectory(double velocity, double angle_radians) {
    // Simple v^2 * sin(2*theta) / g
    return (velocity * velocity * sin(2.0 * angle_radians)) / 9.81;
}
EOF

    cat << 'EOF' > /home/user/src/mathops_v2.c
#include <math.h>
double calculate_trajectory(double velocity, double angle_radians) {
    // v^2 * sin(2*theta) / g - small air resistance constant
    return ((velocity * velocity * sin(2.0 * angle_radians)) / 9.81) * 0.95;
}
EOF

    cat << 'EOF' > /home/user/release_manifest.json
{
  "release_name": "MarsLander-Beta",
  "dependencies": {
    "mathops": ">=2.0.0"
  }
}
EOF

    chown -R user:user /home/user/src
    chown -R user:user /home/user/libs
    chown user:user /home/user/release_manifest.json

    chmod -R 777 /home/user
