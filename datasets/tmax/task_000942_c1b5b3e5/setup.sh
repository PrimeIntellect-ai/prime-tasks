#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/source1.csv
id,text,date
101,"Great product! Loved it.",2023-01-01
102,"Terrible, worst experience ever!!!",2023-01-02
105,"I am ambivalent.",2023-01-03
EOF

    cat << 'EOF' > /home/user/data/source2.csv
req_id,review_body,timestamp
103,"It is okay, not bad.",1672617600
104,"Highly recommended item.",1672704000
106,"OK.",1672790400
EOF

    cat << 'EOF' > /home/user/data/meta.csv
item_id,category_code
101,A1
102,B2
103,A1
104,C3XYZ
106,D
EOF

    chmod -R 777 /home/user
