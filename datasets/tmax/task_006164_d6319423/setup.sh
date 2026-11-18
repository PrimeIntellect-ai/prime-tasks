#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/build
    mkdir -p /home/user/project/artifacts

    cat << 'EOF' > /home/user/project/src/math_ops.c
int add(int a, int b) {
    return a + b;
}
EOF

    cat << 'EOF' > /home/user/project/src/transform.c
int double_val(int a) {
    return a * 2;
}
EOF

    cat << 'EOF' > /home/user/project/deps.json
{
    "transform": ["math_ops"],
    "math_ops": [],
    "test_integration": ["transform", "math_ops"]
}
EOF

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
