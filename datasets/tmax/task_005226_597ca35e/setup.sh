#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/users.csv
user_id,region,account_type
1,NA,free
2,EU,premium
3,NA,premium
4,APAC,free
EOF

    cat << 'EOF' > /home/user/data/messages.csv
msg_id,user_id,timestamp,message_text
101,1,2023-10-01 10:00:00,Hello world!
102,2,2023-10-01 10:05:00,Hi there Europe
103,1,invalid_time,Bad time string so drop me
104,3,2023-10-01 10:10:00,This is a test message for NA region
105,2,2023-10-01 10:15:00,   
106,4,2023-10-01 09:00:00,APAC check
EOF

    chmod -R 777 /home/user
