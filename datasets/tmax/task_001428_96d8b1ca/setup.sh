#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libgsl-dev libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/network.txt
0 1 1 0
1 0 1 1
1 1 0 0
0 1 0 0
EOF

    cat << 'EOF' > /home/user/spectra.csv
NodeID,Wavelength,Absorbance
0,1.0,1.5
0,2.0,2.5
1,1.0,2.1
1,2.0,4.0
1,3.0,6.1
2,1.0,3.0
2,2.0,4.0
3,1.0,0.5
3,2.0,1.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
