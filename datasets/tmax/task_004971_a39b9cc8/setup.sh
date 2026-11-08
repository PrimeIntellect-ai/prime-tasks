#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_graph.csv
source,target,latency,data_tags
Web,Gateway,2,PII
Gateway,Auth,5,PII
Gateway,Catalog,3,Public
Auth,ProfileDB,10,PII
Auth,Logs,2,Opaque
Gateway,Cache,1,PII
Cache,ProfileDB,20,PII
Web,Proxy,1,PII
Proxy,ProfileDB,12,PII
Proxy,Logs,4,Public
Web,FastLane,1,PII
FastLane,ProfileDB,5,Internal
EOF

    chmod -R 777 /home/user
