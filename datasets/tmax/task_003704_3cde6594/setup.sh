#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/noisy_descriptions.csv
id,description,confidence
1,This is a high quality mechanical keyboard with red switches.,0.95
2,This is a high quality mechanical keyboard with red switches.,0.90
3,Short desc,0.99
4,A premium ergonomic wireless mouse for gaming and productivity.,0.40
5,A premium ergonomic wireless mouse for gaming and productivity.,0.88
6,An ergonomic wireless mouse designed for premium gaming and work.,0.82
7,A high-resolution 4K monitor perfect for video editing.,0.92
8,High quality mechanical keyboard with blue switches.,0.85
9,Standard office chair with lumbar support and adjustable armrests.,0.91
10,Office chair with lumbar support and armrests.,0.91
EOF

    chmod -R 777 /home/user
