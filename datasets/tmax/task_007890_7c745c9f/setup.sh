#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest packaging websockets

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/libv1.c
const char* get_version() {
    return "1.8.5";
}
EOF

    cat << 'EOF' > /tmp/libv2.c
const char* get_version() {
    return "2.1.0-beta";
}
int calculate_hash(int input_val) {
    return input_val * 42 + 7;
}
EOF

    gcc -shared -o /home/user/libv1.so -fPIC /tmp/libv1.c
    gcc -shared -o /home/user/libv2.so -fPIC /tmp/libv2.c

    chmod -R 777 /home/user
