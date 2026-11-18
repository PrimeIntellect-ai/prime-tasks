#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'DATA' > /home/user/config_changes.csv
1678886400,Server-Port!,8080
1678886400,SERVER_PORT_,8080
1678886401,DB Hostname,db.local
1678886402,Feature.Toggle.1,true
1678886402,Feature Toggle 1,false
1678886403,Cache_Size_MB,1024
1678886403,Cache-Size-MB,1024
1678886403,cache_size_mb,1024
DATA

    chmod -R 777 /home/user
