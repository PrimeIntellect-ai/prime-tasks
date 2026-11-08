#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/data/raw_sensor.csv
id,timestamp,temp,humidity,notes
1,2023-10-01 10:00,22.5,45.0,"Normal operation"
2,2023-10-01 10:05,48.2,50.1,"Spike detected
checking equipment"
3,2023-10-01 10:10,21.0,46.0,"Note with
embedded newline
and another"
4,2023-10-01 10:15,46.5,44.0,"Another note"
5,2023-10-01 10:20,20.5,45.5,"End of shift"
EOF

    chmod -R 777 /home/user
