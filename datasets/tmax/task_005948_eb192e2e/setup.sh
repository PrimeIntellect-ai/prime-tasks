#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming_configs
    mkdir -p /home/user/processed_configs

    # Create JSON config
    cat << 'EOF' > /home/user/incoming_configs/web.json
{
  "app_name": "nginx",
  "version": "1.21.0",
  "port": 80
}
EOF

    # Create XML config
    cat << 'EOF' > /home/user/incoming_configs/db.xml
<root>
  <app_name>postgres</app_name>
  <version>14.2</version>
  <max_connections>100</max_connections>
</root>
EOF

    # Create CSV config
    cat << 'EOF' > /home/user/incoming_configs/cache.csv
app_name,version,memory
redis,6.2.6,2GB
EOF

    chown -R user:user /home/user/incoming_configs
    chown -R user:user /home/user/processed_configs
    chmod -R 777 /home/user
