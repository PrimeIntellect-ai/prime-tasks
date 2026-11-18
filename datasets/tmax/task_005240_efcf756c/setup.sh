#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/inputs /home/user/output /home/user/logs

    cat << 'EOF' > /home/user/inputs/events.csv
event_id,timestamp,raw_description
1,2023-10-15T14:32:15Z,RESTART: Server initiated reboot!
2,2023-10-15T14:32:45Z,WARNING CPU threshold exceeded.
3,2023-10-15T14:33:10Z,Deploying new-container version 2.
4,2023-10-15T14:35:05Z,CRASH database connection lost?
EOF

    cat << 'EOF' > /home/user/inputs/metrics.csv
unix_time,cpu_load,ram_usage
1697380330,85.5,60.2
1697380365,90.1,61.0
1697380390,75.0,65.5
1697380500,20.5,40.0
EOF

    chown -R user:user /home/user/inputs /home/user/output /home/user/logs
    chmod -R 777 /home/user
