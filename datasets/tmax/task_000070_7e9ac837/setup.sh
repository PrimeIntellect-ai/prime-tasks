#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/search_logs.txt
2023-10-01 10:05:12 | U123 | What is the best, most amazing pizza?!
2023-10-01 10:07:00 | U007 | Top secret agent gadgets...
2023-10-01 10:15:30 | U123 | Where to buy pizza!?
2023-10-01 10:20:00 | U999 | Hello world
2023-10-01 10:25:00 | U007 | gadgets for   missions
2023-10-01 10:30:00 | U123 | Is NY pizza > Chicago pizza?
2023-10-01 10:35:00 | U555 | 
2023-10-01 10:40:00 | U555 | ??? !!!
2023-10-01 10:45:00 | U007 | 007 movie release date 2024
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
