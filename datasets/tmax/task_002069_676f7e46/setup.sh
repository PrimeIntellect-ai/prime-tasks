#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/input_data
    mkdir -p /home/user/output_data

    cat << 'EOF' > /home/user/input_data/site_1.csv
timestamp,sensor_alpha,sensor_beta,sensor_gamma,notes
2023-01-01T10:00:00Z,10.0,20.0,30.0,"Start of year
system check"
2023-01-01T10:05:00Z,12.0,,32.0,"Normal"
2023-01-01T10:10:00Z,14.0,22.0,34.0,"Normal
with extra newline"
2023-01-01T10:15:00Z,16.0,24.0,36.0,"End of run"
EOF

    cat << 'EOF' > /home/user/input_data/site_2.csv
timestamp,sensor_alpha,sensor_beta,sensor_gamma,notes
2023-01-01T10:00:00Z,100.0,200.0,300.0,"All good"
2023-01-01T10:05:00Z,110.0,210.0,,"Missing gamma
needs fixing"
2023-01-01T10:10:00Z,120.0,220.0,320.0,"Restored"
EOF

    cat << 'EOF' > /home/user/input_data/site_3.csv
timestamp,sensor_alpha,sensor_beta,sensor_gamma,notes
2023-01-01T10:00:00Z,1.0,2.0,3.0,"Site 3 active"
EOF

    cat << 'EOF' > /home/user/input_data/site_4.csv
timestamp,sensor_alpha,sensor_beta,sensor_gamma,notes
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
