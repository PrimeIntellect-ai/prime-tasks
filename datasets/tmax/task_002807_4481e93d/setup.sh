#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/configs.csv
timestamp,server_id,LogLevel,MaxWorkers,CacheSize,Gzip
162000,app-web-01,INFO,4,1024,on
162000,app-web-02,INFO,4,1024,on
162000,db-node-01,WARN,8,4096,off
162060,app-web-01,DEBUG,4,1024,on
162060,app-web-02,INFO,8,1024,on
162060,db-node-01,WARN,8,8192,off
162120,app-web-01,DEBUG,6,2048,on
162120,app-web-02,INFO,8,1024,off
162120,db-node-01,WARN,8,8192,off
162180,app-web-01,INFO,6,2048,on
162180,app-web-02,INFO,8,2048,off
162180,db-node-01,ERROR,8,8192,on
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
