#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user

cat << 'EOF' > /home/user/knowledge_base.tsv
Pub_101	authored_by	Person_1
Pub_101	authored_by	Person_2
Pub_101	authored_by	Person_3
Pub_102	authored_by	Person_1
Pub_102	authored_by	Person_4
Pub_103	authored_by	Person_2
Pub_103	covers_topic	Topic_X
Pub_104	authored_by	Person_3
Pub_104	covers_topic	Topic_Y
Pub_105	authored_by	Person_4
Pub_105	covers_topic	Topic_X
Pub_106	authored_by	Person_5
Pub_106	covers_topic	Topic_X
Pub_107	authored_by	Person_1
Pub_107	covers_topic	Topic_X
EOF

chown -R user:user /home/user/knowledge_base.tsv
chmod -R 777 /home/user
