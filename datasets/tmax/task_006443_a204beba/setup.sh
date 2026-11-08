#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    mkdir -p /home/user/input

    cat << 'EOF' > /home/user/input/data1.csv
A1B2C,2023-10-12,INFO,User logged in successfully.
X9Y8Z,2023-10-12,WARN,Failed to load module <span class="error">auth</span>.
EOF

    cat << 'EOF' > /home/user/input/data2.csv
M4N5P,2023-10-1,INFO,Starting service.
EOF

    cat << 'EOF' > /home/user/input/data3.csv
Q1W2E,2023-10-13,ERROR,Database connection lost! <b>Retry in 5s</b>...
P0O9I,2023-10-13,INFO,Query execution took 45ms.
EOF

    cat << 'EOF' > /home/user/input/data4.csv
Z1X2C,2023-10-14,DEBUG,Variable x = 10.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
