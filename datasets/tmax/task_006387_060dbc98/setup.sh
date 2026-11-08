#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/equations.csv
id,expression
1,2x + 3 = 7
2,y = m*x + c
3,a^2 + b^2 = c^2
4,f(x) = 100 / (x - 5)
5,loss = (y - pred)^2
EOF

    chmod -R 777 /home/user
