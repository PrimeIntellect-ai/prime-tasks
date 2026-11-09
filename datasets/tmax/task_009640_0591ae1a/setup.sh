#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/simulation
    cat << 'EOF' > /home/user/simulation/simulate.py
import json

def process_kinematics(forces):
    velocity = 5.0
    dt = 0.1
    mass = 2.0
    positions = [0.0]

    for i in range(len(forces) - 1):
        acceleration = forces[i] / mass
        velocity += acceleration * dt

        positions.append(positions[-1] + velocity * dt)

    return positions[-1]

if __name__ == "__main__":
    forces = [-50.0, -100.0, -20.0, 20.0, 40.0, 60.0]
    final_pos = process_kinematics(forces)

    with open('/home/user/result.json', 'w') as f:
        json.dump({"final_position": final_pos}, f)
EOF
    chmod +x /home/user/simulation/simulate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
