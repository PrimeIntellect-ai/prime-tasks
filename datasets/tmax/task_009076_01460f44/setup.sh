#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/users.csv
id,name
1,Alice
2,Bob
3,Charlie
4,Diana
5,Eve
EOF

    cat << 'EOF' > /home/user/follows.csv
follower_id,followed_id
1,2
2,3
2,4
1,5
5,4
3,1
EOF

    cat << 'EOF' > /home/user/posts.csv
post_id,author_id,views
101,1,50
102,1,100
103,2,200
104,3,0
105,5,500
EOF

    chmod -R 777 /home/user
