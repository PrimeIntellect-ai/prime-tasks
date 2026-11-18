#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y libgsl-dev gcc make

    # Create user
    useradd -m -s /bin/bash user || true

    # Create task directories and files
    mkdir -p /home/user/sim_data
    cat << 'EOF' > /home/user/sim_data/matrix.txt
1.0 2.0 3.0
4.0 5.0 6.0
7.0 8.0 9.0
10.0 11.0 12.0
EOF

    # Set permissions
    chmod -R 777 /home/user
