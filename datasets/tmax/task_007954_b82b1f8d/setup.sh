#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk sed grep findutils bsdmainutils coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/config_tree/app1
mkdir -p /home/user/config_tree/app2/module
mkdir -p /home/user/config_tree/legacy
mkdir -p /home/user/config_tree/links

cat << 'EOF' > /home/user/config_tree/app1/settings.conf
# App 1 settings
app_name=NginxServer
version=1.18.0
workers=4
EOF

cat << 'EOF' > /home/user/config_tree/app2/module/service.txt
APP_NAME=DatabaseWorker
VERSION=9.4
# End of file
EOF

python3 -c '
with open("/home/user/config_tree/legacy/cache.bin", "wb") as f:
    f.write(b"\x42\x43\x46\x47\x03CacheNode\x00extra_junk_data")
with open("/home/user/config_tree/app1/lb.state", "wb") as f:
    f.write(b"\x42\x43\x46\x47\x0CLoadBalancer\x00")
'

echo "Just some random text." > /home/user/config_tree/legacy/readme.md

ln -s /home/user/config_tree/app1/settings.conf /home/user/config_tree/links/settings_link.conf

ln -s /home/user/config_tree/links/loop1 /home/user/config_tree/links/loop1

ln -s /home/user/config_tree/links/loop2b /home/user/config_tree/links/loop2a
ln -s /home/user/config_tree/links/loop2a /home/user/config_tree/links/loop2b

ln -s /home/user/does_not_exist /home/user/config_tree/links/broken_link

chown -R user:user /home/user/config_tree
chmod -R 777 /home/user
