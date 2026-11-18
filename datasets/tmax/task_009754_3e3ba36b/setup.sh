#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/feedback.csv
id,timestamp,text,rating
1,2023-10-01,Great product, but slow shipping.,4
2,2023-10-02,Terrible! I absolutely hate it.,1
3,2023-10-03,Very good! I will buy again.,5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
