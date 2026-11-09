#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron jq gawk
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/users.csv
id,name,email,join_date
1,alice smith,Alice@Example.com,2023-01-15
2,BOB JONES,bob@example.com,12/31/2022
3,Carol White,carol@example.org,2023-02-01
4,Alice S.,ALICE@EXAMPLE.COM,01/15/2023
5,dave brown,Dave.Brown@example.com,10/10/2021
6,eve black,eve@example.com,2023-03-05
7,Fake Bob,BOB@example.com,12/31/2022
EOF

    cat << 'EOF' > /home/user/data/activity.jsonl
{"user_email": "alice@example.com", "action": "login"}
{"user_email": "bob@example.com", "action": "click"}
{"user_email": "alice@example.com", "action": "logout"}
{"user_email": "dave.brown@example.com", "action": "view"}
{"user_email": "eve@example.com", "action": "login"}
{"user_email": "eve@example.com", "action": "click"}
{"user_email": "eve@example.com", "action": "logout"}
{"user_email": "unknown@example.com", "action": "bounce"}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
