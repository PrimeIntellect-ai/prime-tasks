#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_sensors.csv
sensor_id,recorded_at,value,unit
S1,2023-10-01T10:00:00Z,68.0,F
S2,10/01/2023 11:30,ERR,C
S3,10/01/2023 12:00,140.0,F
S1,2023-10-01T13:00:00Z,15.5,C
S4,BAD_TIME,10.0,C
S2,10/02/2023 09:15,32.0,F
EOF

    # Use base64 to avoid Apptainer build variable syntax errors with double braces
    echo "IyBTZW5zb3IgQ2xlYW5pbmcgUmVwb3J0ClRvdGFsIHJlY29yZHMgcHJvY2Vzc2VkOiB7e1RPVEFMX1BST0NFU1NFRH19ClZhbGlkIHJlY29yZHM6IHt7VE9UQUxfVkFMSUR9fQpSZWplY3RlZCByZWNvcmRzOiB7e1RPVEFMX1JFSkVDVEVEfX0KQXZlcmFnZSBUZW1wZXJhdHVyZSAoQyk6IHt7QVZHX1RFTVBfQ319Cg==" | base64 -d > /home/user/report_template.txt

    chown -R user:user /home/user
    chmod -R 777 /home/user
