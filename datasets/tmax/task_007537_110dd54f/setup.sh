#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sudo
    pip3 install pytest csvkit

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    mkdir -p /home/user/config_tracker

    cat << 'EOF' > /home/user/config_tracker/changes.csv
timestamp,server_id,config_key,config_value,size_bytes
2023-10-01T10:00:00Z,srv-01,DB Port,8080,10
2023-10-01T10:05:00Z,srv-01,Max Connections,"{
  ""max"": 500,
  ""min"": 10
}",50
2023-10-01T10:10:00Z,srv-02,Cache Size,1024,20
2023-10-01T10:15:00Z,srv-01,Timeout Policy,"500ms",60
2023-10-01T10:20:00Z,srv-01,SSL Cert,"-----BEGIN CERTIFICATE-----
MIID...
-----END CERTIFICATE-----",200
2023-10-01T10:25:00Z,srv-02,Workers,4,20
2023-10-01T10:30:00Z,srv-02,Features,"{
  ""beta"": true
}",100
EOF

    chmod -R 777 /home/user
