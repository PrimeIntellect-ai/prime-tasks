#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/config_events.log
[2023-10-01 10:00:00] SERVICE=Database DEPENDS_ON= CONFIG=port:5432
[2023-10-01 10:00:05] SERVICE=Cache DEPENDS_ON= CONFIG=port:6379
[2023-10-01 10:00:00] SERVICE=Database DEPENDS_ON= CONFIG=port:5432
[2023-10-01 10:01:00] SERVICE=Backend DEPENDS_ON=Database,Cache CONFIG=workers:4
[2023-10-01 10:01:30] SERVICE=Database DEPENDS_ON= CONFIG=user:admin
[2023-10-01 10:02:00] SERVICE=Frontend DEPENDS_ON=Backend CONFIG=theme:light
[2023-10-01 10:01:00] SERVICE=Backend DEPENDS_ON=Database,Cache CONFIG=workers:4
[2023-10-01 10:05:00] SERVICE=Frontend DEPENDS_ON=Backend CONFIG=theme:dark
[2023-10-01 10:06:00] SERVICE=Backend DEPENDS_ON=Database,Cache CONFIG=timeout:30s
[2023-10-01 10:07:00] SERVICE=Cache DEPENDS_ON= CONFIG=max_memory:2G
[2023-10-01 09:59:00] SERVICE=Database DEPENDS_ON= CONFIG=port:5431
EOF

    chmod -R 777 /home/user
