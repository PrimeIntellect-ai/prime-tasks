#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/etl_lineage.tsv
raw_users	stg_users
stg_users	int_user_purchases
int_user_purchases	fct_sales
fct_sales	mart_revenue
raw_users	stg_events
stg_events	fct_clicks
raw_users	dim_fast_track
dim_fast_track	mart_revenue
stg_users	dim_users
dim_users	fct_sales
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
