#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_sensor_data.csv
timestamp,sensor_id,reading,notes
2023-10-01T10:00:00Z,alpha-1,10.5,"Start of   run
with newlines"
2023-10-01T10:01:00Z,alpha-1,,"missing
reading"
2023-10-01T10:02:00Z,alpha-1,12.5,"normal"
2023-10-01T10:02:00Z,alpha-1,15.0,"duplicate row  "
2023-10-01T10:00:30Z,beta-2,5.0,"beta notes"
2023-10-01T10:01:30Z,BETA-2,,"another
missing"
2023-10-01T10:03:00Z,gamma-3,,"totally empty"
EOF

    cat << 'EOF' > /home/user/expected_cleaned_sensor_data.csv
timestamp,sensor_id,reading,notes
2023-10-01T10:00:00Z,ALPHA-1,10.50,Start of run with newlines
2023-10-01T10:00:30Z,BETA-2,5.00,beta notes
2023-10-01T10:01:00Z,ALPHA-1,11.50,missing reading
2023-10-01T10:01:30Z,BETA-2,5.00,another missing
2023-10-01T10:02:00Z,ALPHA-1,12.50,normal
2023-10-01T10:03:00Z,GAMMA-3,0.00,totally empty
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
