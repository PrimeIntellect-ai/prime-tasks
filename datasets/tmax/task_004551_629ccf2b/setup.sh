#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_reviews.csv
timestamp,user_id,review_text
1000,u1,Great product! Highly recommend.
1001,u2,TERRIBLE service... won't buy again.
1002,u2,TERRIBLE service... won't buy again.
1003,u3,Okay, but 100% too expensive  
1004,u4,I LOVE IT!!!
1005,u5,Wait, what?
1006,u5,Duplicate user
1007,u6,  Multiple   spaces   here  
EOF

    chmod -R 777 /home/user
