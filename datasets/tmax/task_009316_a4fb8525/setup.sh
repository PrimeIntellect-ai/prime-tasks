#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc parallel coreutils findutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_target.awk
BEGIN {
    v = 0;
    k = 0.15;
    dt = 0.1;
    g = 9.8;
    printf "%.1f %.6f\n", 0.0, v;
    for (i=1; i<=100; i++) {
        v = v + dt * (g - k * v * v);
        printf "%.1f %.6f\n", i*dt, v;
    }
}
EOF

    awk -f /home/user/generate_target.awk > /home/user/target.txt
    rm /home/user/generate_target.awk

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
