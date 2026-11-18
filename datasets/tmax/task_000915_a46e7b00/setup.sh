#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip util-linux jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/configs/app_new.json
{
  "name": "app-backend",
  "port": 8080,
  "version": "1.2.3"
}
EOF

    cat << 'EOF' > /home/user/configs/app_old.json
{
  "name": "app-frontend",
  "version": "0.9.0"
}
EOF

    cat << 'EOF' > /home/user/configs/db_new.csv
key,value
host,localhost
port,5432
version,9.5.1
EOF

    cat << 'EOF' > /home/user/configs/cache_new.xml
<config>
  <memory>1024</memory>
  <version>2.0.0-rc1</version>
</config>
EOF

    cat << 'EOF' > /home/user/configs/web_old.xml
<config>
  <hostname>web.local</hostname>
  <version>1.0.0</version>
</config>
EOF

    touch -d "5 days ago" /home/user/configs/app_old.json
    touch -d "5 days ago" /home/user/configs/web_old.xml

    chown -R user:user /home/user
    chmod -R 777 /home/user
