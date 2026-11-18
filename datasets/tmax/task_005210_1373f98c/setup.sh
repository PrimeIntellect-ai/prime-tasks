#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/output

    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > /home/user/data/sensor_a.csv
timestamp,temp_c
2023-10-01 04:00:00,12.5
2023-10-01 16:00:00,14.5
2023-10-02 08:00:00,10.0
2023-10-03 12:00:00,8.5
EOF

    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/data/sensor_b.csv
timestamp,temp_f
10/01/2023-08:00,59.0
10/01/2023-20:00,53.6
10/02/2023-09:00,50.0
10/04/2023-11:00,41.0
EOF

    cat << 'EOF' > /home/user/template.md
## Report for {DATE}
Min: {MIN} C
Max: {MAX} C
Avg: {AVG} C
EOF

    chmod -R 777 /home/user
