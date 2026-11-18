#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/floor1_temp.csv
timestamp_iso,sensor_id,temperature,hash_id
2023-10-01T10:04:00Z,T1,22.0,h1
2023-10-01T10:04:00Z,T1,22.0,h1
2023-10-01T10:12:00Z,T2,23.0,h2
2023-10-01T10:16:00Z,T1,22.5,h3
2023-10-01T10:48:00Z,T2,24.0,h4
2023-10-01T11:20:00Z,T1,21.0,h5
2023-10-01T11:25:00Z,T2,21.5,h6
2023-10-01T11:20:00Z,T1,99.9,h5
EOF

    cat << 'EOF' > /home/user/data/floor2_humidity.csv
epoch_ts,device_id,humidity,req_id
1696154580,H1,45.0,r1
1696154640,H2,46.0,r2
1696156500,H1,42.0,r3
1696156500,H1,99.0,r3
1696157400,H2,40.0,r4
1696159200,H1,38.0,r5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
