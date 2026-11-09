#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq xmlstarlet sudo
    pip3 install pytest

    mkdir -p /home/user/configs /home/user/data /home/user/output

    cat << 'EOF' > /home/user/configs/settings.json
{
  "database": {
    "connection": {
      "port": 5432,
      "host": "localhost"
    },
    "pool_size": 20
  },
  "logging": {
    "level": "INFO"
  }
}
EOF

    cat << 'EOF' > /home/user/configs/system.xml
<?xml version="1.0" encoding="UTF-8"?>
<system>
  <network>
    <timeout>30</timeout>
    <retries>3</retries>
  </network>
  <security>
    <tls_enabled>true</tls_enabled>
  </security>
</system>
EOF

    cat << 'EOF' > /home/user/configs/env.csv
key,value
MAX_MEMORY,4G
CACHE_DIR,/tmp/cache
OLD_SETTING,true
EOF

    cat << 'EOF' > /home/user/data/history.log
2023-08-15 10:00:00 [settings.json] [database.connection.port] [UPDATE]
2023-09-01 11:00:00 [settings.json] [database.connection.port] [UPDATE]
2023-09-05 12:00:00 [settings.json] [database.connection.host] [UPDATE]
2023-09-10 13:00:00 [system.xml] [system.network.timeout] [UPDATE]
2023-09-12 14:00:00 [system.xml] [system.network.timeout] [UPDATE]
2023-09-15 15:00:00 [env.csv] [MAX_MEMORY] [UPDATE]
2023-10-02 16:00:00 [env.csv] [MAX_MEMORY] [UPDATE]
2023-10-05 17:00:00 [settings.json] [database.pool_size] [UPDATE]
2023-10-06 18:00:00 [settings.json] [database.connection.port] [UPDATE]
2023-10-10 19:00:00 [system.xml] [system.network.retries] [UPDATE]
2023-10-11 20:00:00 [system.xml] [system.security.tls_enabled] [UPDATE]
2023-10-15 21:00:00 [env.csv] [DELETED_KEY] [UPDATE]
2023-10-20 22:00:00 [settings.json] [logging.level] [DELETE]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
