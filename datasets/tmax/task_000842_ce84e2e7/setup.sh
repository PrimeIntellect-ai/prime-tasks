#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget gcc make libc6-dev
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/nodes.txt
1|User|{"status":"active","age":30}
2|User|{"status":"inactive","age":25}
3|Group|{"status":"active","name":"Admins"}
4|Group|{"status":"active","name":"Users"}
5|Resource|{"status":"active","type":"Server"}
6|Resource|{"status":"archived","type":"Database"}
7|User|{"status":"active","age":45}
EOF

cat << 'EOF' > /home/user/edges.txt
1|3|MEMBER_OF|15
1|4|MEMBER_OF|5
2|4|MEMBER_OF|20
3|4|PARENT_OF|50
3|5|HAS_ACCESS|10
4|5|HAS_ACCESS|8
7|3|MEMBER_OF|12
7|6|HAS_ACCESS|25
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
