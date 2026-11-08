#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/events.csv
timestamp_sec,language,content
100,en,Hello!
100,es,¡Hola!
101,en,Short
102,en,A
102,en,B
102,en,C
102,fr,Bonjour
102,fr,Oui
102,ja,こんにちは
102,ja,はい
103,en,Normal
104,zh,你好
104,zh,世界
104,zh,测试
104,zh,数据
104,zh,管道
104,zh,工程师
104,en,Wow that is a lot
EOF

    chmod -R 777 /home/user
