#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gzip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data_dumps/

echo "Just some random text data" > /home/user/data_dumps/dump_01
head -c 100 /dev/urandom > /home/user/data_dumps/dump_03
echo '{"category": "database", "mount_path": "/mnt/fake"}' > /home/user/data_dumps/dump_06

cat << 'EOF' > /tmp/json1.json
[
  {"id": 1, "category": "web", "mount_path": "/var/www/html"},
  {"id": 2, "category": "database", "mount_path": "/mnt/data/postgres_main"},
  {"id": 3, "category": "cache", "mount_path": "/mnt/data/redis"}
]
EOF

cat << 'EOF' > /tmp/json2.json
[
  {"id": 4, "category": "database", "mount_path": "/mnt/data/mysql_legacy"},
  {"id": 5, "category": "database", "mount_path": "/mnt/data/mongo_analytics"}
]
EOF

cat << 'EOF' > /tmp/json3.json
[
  {"id": 6, "category": "assets", "mount_path": "/mnt/nfs/images"}
]
EOF

gzip -c /tmp/json1.json > /home/user/data_dumps/dump_02
gzip -c /tmp/json2.json > /home/user/data_dumps/dump_05
gzip -c /tmp/json3.json > /home/user/data_dumps/dump_08

python3 -c "open('/home/user/data_dumps/dump_09', 'wb').write(b'\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03\x01\x02\x03')"

rm /tmp/json*.json

chown -R user:user /home/user/data_dumps/
chmod -R 777 /home/user
