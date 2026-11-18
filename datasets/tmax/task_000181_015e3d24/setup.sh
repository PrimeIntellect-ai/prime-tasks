#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_dependencies.csv
extract_users,clean_users
extract_users,transform_users
clean_users,transform_users
transform_users,load_users
load_users,aggregate_metrics
extract_orders,clean_orders
clean_orders,transform_orders
transform_orders,load_orders
load_orders,aggregate_metrics
clean_users,transform_orders
aggregate_metrics,report_generation
extract_users,fast_track_load
fast_track_load,aggregate_metrics
EOF

    chmod -R 777 /home/user
