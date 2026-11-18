#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang make
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/locales.csv
id,lang,text
101,en,You have 1234 apples.
102,en,There are 99 problems.
103,en,0 issues found.
201,ja,テスト１２３
202,ja,テスト９９
203,ja,０の問題
301,ar,اختبار ١٢٣
302,ar,اختبار ٩٨
303,ar,٠ مشاكل
401,ru,У вас 1234 яблока.
402,ru,У вас 555 яблок.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
