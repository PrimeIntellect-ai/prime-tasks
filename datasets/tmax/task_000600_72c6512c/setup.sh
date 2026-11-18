#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_config_events.csv
1680000100,database_url,a1b2c3d4,SUCCESS
1680000105,database_url,e5f6g7h8,FAILED
1680000102,database_url,9i0j1k2l,SUCCESS
1680000090,api_timeout,z9y8x7w6,SUCCESS
1680000115,api_timeout,v5u4t3s2,SUCCESS
1680000110,worker_count,r1q2p3o4,FAILED
1680000120,worker_count,n5m6l7k8,SUCCESS
1680000125,worker_count,j9i0h1g2,FAILED
1680000120,worker_count,n5m6l7k8,SUCCESS
1680000095,max_retries,f3e4d5c6,SUCCESS
1680000001,cache_host,b7a8z9y0,SUCCESS
1680000005,cache_host,x1w2v3u4,FAILED
EOF

    chmod -R 777 /home/user
