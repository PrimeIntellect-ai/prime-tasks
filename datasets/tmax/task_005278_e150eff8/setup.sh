#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas pyarrow

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/chat_app.jsonl
{"time": "2023-10-01T10:00:00Z", "uid": "U100", "msg": "Hello, my order failed!!", "platform": "app"}
{"time": "2023-10-01T10:15:00Z", "uid": "U100", "msg": "Can you check order #992?", "platform": "app"}
{"time": "2023-10-01T11:05:00Z", "uid": "U100", "msg": "Any updates?", "platform": "app"}
{"time": "2023-10-01T09:30:00Z", "uid": "U102", "msg": "Reset password pls.", "platform": "app"}
EOF

    cat << 'EOF' > /home/user/data/email_support.csv
created_at,customer_id,content,origin
2023-10-01T10:30:00Z,U100,"I also emailed about order #992. Thx.",email
2023-10-01T12:00:00Z,U101,"Refund requested for item A.",email
2023-10-01T08:00:00Z,U101,"Where is my package?",email
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
