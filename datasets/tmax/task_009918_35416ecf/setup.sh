#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/etl_logs.tsv
2023-10-01T10:00:00Z	TX1001	en	Hello World	150	512	1024
2023-10-01T10:01:00Z	TX1002	fr	Bonjour le monde	200	1024	2048
2023-10-01T10:02:00Z	TX1001	en	Hello World	999	999	999
2023-10-01T10:03:00Z	TX1003	en	How are you?	100	256	512
2023-10-01T10:04:00Z	TX1004	zh	你好，世界	300	2048	4096
2023-10-01T10:05:00Z	TX1002	fr	Bonjour le monde	888	888	888
2023-10-01T10:06:00Z	TX1005	es	Hola Mundo	120	512	1024
2023-10-01T10:07:00Z	TX1006	zh	欢迎	200	1024	2048
2023-10-01T10:08:00Z	TX1005	es	Hola Mundo	777	777	777
EOF

chmod -R 777 /home/user
