#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sim

    cat << 'EOF' > /home/user/sim/integrator.py
def integrate(a, b, dt):
    # Hidden stability limit formula to simulate divergent ODE
    # limit = 0.45 / a + 0.1 * b
    limit = (0.45 / a) + (0.1 * b)
    # Floating point safe check for precision 0.001
    if dt > limit + 1e-7:
        return float('inf')
    return 1.0
EOF

    cat << 'EOF' > /home/user/sim/params.json
[
  {"id": 1, "a": 1.0, "b": 1.0},
  {"id": 2, "a": 2.0, "b": 0.5},
  {"id": 3, "a": 0.5, "b": 3.0},
  {"id": 4, "a": 3.0, "b": 2.0},
  {"id": 5, "a": 1.5, "b": 1.5}
]
EOF

    chown -R user:user /home/user/sim
    chmod -R 777 /home/user
