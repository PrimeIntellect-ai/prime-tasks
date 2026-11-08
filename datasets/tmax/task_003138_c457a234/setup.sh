#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_audit.log
[2023-11-01 08:12:45] admin_alice CONFIG_UPDATE: Changed parameter 'MaxConnections' on server 'web-01'
[2023-11-01 08:45:12] sysop_bob CONFIG_UPDATE: Changed parameter 'Timeout' on server 'db-02'
[2023-11-01 09:10:00] admin_alice CONFIG_UPDATE: Changed parameter 'CacheSize' on server 'web-01'
[2023-11-01 11:22:33] auto_deploy CONFIG_UPDATE: Changed parameter 'FeatureFlagX' on server 'app-05'
[2023-11-01 11:25:00] auto_deploy CONFIG_UPDATE: Changed parameter 'FeatureFlagY' on server 'app-05'
[2023-11-01 11:59:59] admin_alice CONFIG_UPDATE: Changed parameter 'LogLevel' on server 'web-01'
[2023-11-01 12:05:00] sysop_bob CONFIG_UPDATE: Changed parameter 'RetryLimit' on server 'worker-01'
[2023-11-01 14:30:00] admin_alice CONFIG_UPDATE: Changed parameter 'MemoryLimit' on server 'cache-01'
EOF

    chmod -R 777 /home/user
