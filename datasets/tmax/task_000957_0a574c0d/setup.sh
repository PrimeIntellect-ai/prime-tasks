#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    dd if=/dev/urandom of=/home/user/backup.img bs=1M count=1
    cat << 'EOF' >> /home/user/backup.img
# DIAGNOSTIC_SCRIPT_START
def calculate_index(x, current_sum):
    if x == 0.0:
        return current_sum
    return calculate_index(x - 0.1, current_sum + x*x)
print(calculate_index(1.0, 0.0))
# DIAGNOSTIC_SCRIPT_END
EOF
    dd if=/dev/urandom bs=1M count=1 >> /home/user/backup.img

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
