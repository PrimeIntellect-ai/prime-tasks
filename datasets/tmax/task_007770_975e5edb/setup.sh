#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_updates.csv
2023-01-01T00:00,DEV,feature_x,on
2023-01-01T01:00,DEV,feature_x,off
2023-01-01T02:00,DEV,feature_x,on
2023-01-01T03:00,DEV,feature_x,off
2023-01-01T04:00,DEV,feature_x,on
2023-01-01T00:00,DEV,cache_size,100
2023-01-01T01:00,DEV,cache_size,200
2023-01-01T02:00,DEV,cache_size,100
2023-01-01T00:00,PROD,log_level,info
2023-01-01T01:00,PROD,log_level,debug
2023-01-01T02:00,PROD,log_level,info
2023-01-01T03:00,PROD,log_level,debug
2023-01-01T04:00,PROD,log_level,info
2023-01-01T00:00,PROD,db_timeout,30
2023-01-01T01:00,PROD,db_timeout,60
2023-01-01T02:00,PROD,db_timeout,30
2023-01-01T03:00,PROD,db_timeout,60
2023-01-01T04:00,PROD,db_timeout,30
2023-01-01T00:00,STAGING,workers,2
2023-01-01T01:00,STAGING,workers,4
2023-01-01T02:00,STAGING,workers,2
2023-01-01T03:00,STAGING,workers,8
2023-01-01T04:00,STAGING,workers,2
EOF

    chmod -R 777 /home/user
