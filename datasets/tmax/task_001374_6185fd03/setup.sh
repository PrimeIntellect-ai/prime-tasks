#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_reviews.csv
ReviewID,Text,Rating,Price
1,Great product, loved it.,5,10.5
2,Terrible. Do not buy.,1,15.0
3,,3,12.0
4,Okay,8,10.0
5,Very good value for the money.,4,-5.0
6,Average.,3,10.0
7,I am absolutely amazed by the quality of this item.,5,25.0
8,Broke after one use,1,8.0
9,It is fine,3,11.5
10,Not what I expected,2,9.99
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
