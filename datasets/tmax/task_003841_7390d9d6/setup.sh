#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk bc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/X.csv
0.1
0.2
0.3
0.4
0.5
0.6
0.7
0.8
0.9
1.0
EOF

cat << 'EOF' > /home/user/Y.csv
1.22
1.41
1.65
1.80
2.05
2.21
2.45
2.60
2.85
3.01
EOF

chmod -R 777 /home/user
