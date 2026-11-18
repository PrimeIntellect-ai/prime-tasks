#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace
    go mod init data-clean

    cat << 'EOF' > metadata.csv
user_id,username,country
1,alice_smith,UK
2,taro_yamada,JPN
3,helene_d,FRA
4,ahmed_m,EGY
EOF

    python3 -c '
import unicodedata

with open("reviews_1.csv", "w", encoding="utf-8") as f:
    f.write("user_id,review_text\n")
    f.write("1,Good product!\n")
    f.write("3," + unicodedata.normalize("NFD", "Très bien") + "\n")

with open("reviews_2.csv", "w", encoding="utf-8") as f:
    f.write("user_id,review_text\n")
    f.write("2," + unicodedata.normalize("NFD", "スゴイガ") + "\n")
    f.write("4,ممتاز\n")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
