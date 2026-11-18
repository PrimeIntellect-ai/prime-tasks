#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/pages.csv
page_id,url,topic
1,http://example.com/start,Home
2,http://example.com/a,AI
3,http://example.com/b,Data Querying
4,http://example.com/c,Data Querying
5,http://example.com/d,Bash
6,http://example.com/e,Data Querying
7,http://example.com/f,Data Querying
EOF

    cat << 'EOF' > /home/user/links.csv
source_id,target_id
1,2
2,3
1,5
5,4
4,6
3,6
6,7
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
