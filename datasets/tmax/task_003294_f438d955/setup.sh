#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest emoji

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/reviews_raw.csv
review_id,product_id,text,upvotes
r1,PROD_A,I love this! 😍 Very good.,15
r2,PROD_A,素晴らしい製品です👍✨,30
r3,PROD_B,C'est terrible 😡,5
r4,PROD_C,مدهش! 🔥🔥,12
r5,PROD_B,Just okay. 😐,5
r6,PROD_C,Perfect exactly what I needed 💯,20
r7,PROD_C,No emojis here,3
EOF

    chmod -R 777 /home/user
