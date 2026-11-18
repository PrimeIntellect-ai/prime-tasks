#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_chats.csv
interaction_id,raw_text
C001,Customer angry. Issue: Billing. Contact: bob@example.com
C002,Question about account. Issue: billing. Call back.
C003,Need refund. Issue: Refund. email me at alice@test.com
C004,Where is my order? Issue: shipping .
C005,Wrong item. Issue: Shipping. contact me.
C006,Double charged. Issue: BILLING. test@test.com
C007,Package damaged. Issue: refund. No email.
C008,Delayed. Issue: shipping. wait@wait.com
C009,Extra charge. Issue: billing. none
C010,Just a general chat. No issue mentioned.
EOF

    chmod -R 777 /home/user
