#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/candidates

    cat << 'EOF' > /home/user/baseline_spectrum.txt
10Hz	0.10
20Hz	0.20
30Hz	0.40
40Hz	0.20
50Hz	0.10
EOF

    cat << 'EOF' > /home/user/candidates/machine_A.txt
10Hz	0.15
20Hz	0.20
30Hz	0.30
40Hz	0.20
50Hz	0.15
EOF

    cat << 'EOF' > /home/user/candidates/machine_B.txt
10Hz	0.00
20Hz	0.10
30Hz	0.80
40Hz	0.10
50Hz	0.00
EOF

    cat << 'EOF' > /home/user/candidates/machine_C.txt
10Hz	0.10
20Hz	0.25
30Hz	0.30
40Hz	0.25
50Hz	0.10
EOF

    cat << 'EOF' > /home/user/candidates/machine_D.txt
10Hz	0.20
20Hz	0.20
30Hz	0.20
40Hz	0.20
50Hz	0.20
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
