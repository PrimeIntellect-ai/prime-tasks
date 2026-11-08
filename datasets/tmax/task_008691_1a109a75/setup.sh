#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_app.c
#include <stdlib.h>
int main() {
    exit(1);
}
EOF
    gcc /home/user/sensor_app.c -o /home/user/sensor_app
    chmod +x /home/user/sensor_app

    chmod -R 777 /home/user
