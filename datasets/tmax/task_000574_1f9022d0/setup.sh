#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar gzip libc-bin
    pip3 install pytest

    mkdir -p /home/user/config_archive

    cat << 'EOF' > /tmp/system_master_utf8_temp.ini
[MODULE_ALPHA]
description=Legacy cache system
status=active
path=/var/cache/app
param1=café
[MODULE_BETA]
description=Obsolete render engine
status=inactive
param1=naïve
param2=100
[MODULE_GAMMA]
description=Network bridge
status=active
bridge_name=br0
note=façade
[MODULE_DELTA]
description=Unused proxy
status=suspended
proxy_port=8080
[MODULE_EPSILON]
description=Metrics aggregator
status=active
interval=60
tag=piñata
EOF

    iconv -f UTF-8 -t ISO-8859-1 /tmp/system_master_utf8_temp.ini > /home/user/config_archive/system_master.ini

    cd /home/user/config_archive
    tar -czf legacy_configs.tar.gz system_master.ini
    rm system_master.ini /tmp/system_master_utf8_temp.ini

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
