#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip parallel jq findutils
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_sensors/
    mkdir -p /home/user/scripts/

    cat << 'EOF' > /home/user/raw_sensors/batch1.csv
timestamp,s1_temp,s1_vib,s2_temp,s2_vib
2023-10-01T10:00:00,22.1,0.01,23.5,0.02
2023-10-01T10:05:00,22.3,0.02,23.6,0.01
2023-10-01T10:10:00,22.2,0.05,23.8,0.01
EOF

    cat << 'EOF' > /home/user/raw_sensors/batch2.csv
timestamp,s1_temp,s1_vib,s2_temp,s2_vib
2023-10-02T10:00:00,21.0,0.03,24.0,0.04
2023-10-02T10:05:00,21.5,0.02,24.1,0.05
EOF

    cat << 'EOF' > /home/user/raw_sensors/batch3.csv
timestamp,s1_temp,s1_vib,s2_temp,s2_vib
2023-10-03T09:00:00,25.0,0.10,26.0,0.12
2023-10-03T09:05:00,25.1,0.11,26.2,0.13
2023-10-03T09:10:00,25.2,0.12,26.4,0.11
2023-10-03T09:15:00,25.0,0.09,26.1,0.10
EOF

    chmod -R 777 /home/user
