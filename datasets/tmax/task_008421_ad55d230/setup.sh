#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pytz

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_posts.csv
id,timestamp,content
1,2023-11-15T01:15:30Z,Hello world 😊
2,2023-11-15T02:45:00Z,Ｔｈｉｓ ｉｓ ｆｕｌｌｗｉｄｔｈ
3,2023-11-15T03:59:59Z,①②③④⑤⑥⑦⑧⑨⑩
4,2023-11-15T05:20:00Z,مرحبا بالعالم
5,2023-11-15T06:00:00Z,Pneumonoultramicroscopicsilicovolcanoconiosis is long
6,2023-11-15T07:12:00Z,Unrelated short text
7,2023-11-16T13:00:00Z,Just exactly twelve chars
8,2023-11-16T15:59:00Z,Another twelve chars!
EOF

    chmod -R 777 /home/user
