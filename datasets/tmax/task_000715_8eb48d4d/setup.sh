#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/inputs

# Create snapA.json
cat << 'EOF' > /home/user/inputs/snapA.json
[
  {"server_id": "srv1", "service": "web", "port": 8080, "status": "active", "config_string": "workers=4"},
  {"server_id": "srv2", "service": "db", "port": 5432, "status": "active", "config_string": "pool=10"}
]
EOF

# Create snapB.csv
cat << 'EOF' > /home/user/inputs/snapB.csv
server_id,service,port,status,config_string
srv1,web,8080,active,workers=4
srv3,cache,6379,active,maxmem=2G
srv4,api,80,active,limit=100
EOF

# Create snapC.xml
cat << 'EOF' > /home/user/inputs/snapC.xml
<configs>
  <config>
    <server_id>srv5</server_id>
    <service>worker</service>
    <port>90000</port>
    <status>active</status>
    <config_string>threads=8</config_string>
  </config>
  <config>
    <server_id>srv6</server_id>
    <service>metrics</service>
    <port>9090</port>
    <status>maintenance</status>
    <config_string>retention=15d</config_string>
  </config>
  <config>
    <server_id>srv7</server_id>
    <service>log</service>
    <port>5044</port>
    <status>active</status>
    <config_string>level=debug</config_string>
  </config>
  <config>
    <server_id>srv3</server_id>
    <service>cache</service>
    <port>6379</port>
    <status>inactive</status>
    <config_string>maxmem=2G</config_string>
  </config>
</configs>
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
