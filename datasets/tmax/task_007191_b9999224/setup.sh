#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/coefficients.tsv
S1	2.5	0.5
S2	-1.2	10.0
S3	0.0	5.5
EOF

    cat << 'EOF' > /home/user/raw_data.log
ID: S1
X: 2.0
Y: 5.4
---
ID: S2
X: 1.0
Y: 8.9
---
ID: S1
X: 4.0
Y: 10.6
---
ID: S3
X: 10.0
Y: 5.6
---
ID: S2
X: 3.0
Y: 6.4
---
ID: S3
X: -2.0
Y: 5.3
---
ID: S1
X: 0.0
Y: 0.5
---
EOF

    chmod -R 777 /home/user
