#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/blackbox.py
def get_value():
    sum_val = 0.0
    for _ in range(10):
        sum_val += 0.1
    return sum_val

if __name__ == "__main__":
    print(get_value())
EOF

    python3 -m py_compile /tmp/blackbox.py
    mv /tmp/__pycache__/blackbox.*.pyc /home/user/blackbox.pyc
    rm -f /tmp/blackbox.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
