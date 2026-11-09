#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/etl_graph.txt
InitDB ExtractUsers
InitDB ExtractOrders
ExtractUsers TransformUsers
ExtractOrders TransformOrders
TransformUsers JoinData
TransformOrders JoinData
JoinData AggregateMetrics
AggregateMetrics TransformUsers
AggregateMetrics LoadWarehouse
LoadWarehouse NotifySuccess
EOF

    cat << 'EOF' > /home/user/etl_metadata.csv
TaskID,TaskType,Description
InitDB,Setup,Initializes the database
ExtractUsers,Extraction,Extracts user data from API
ExtractOrders,Extraction,Extracts order data from DB
TransformUsers,Transformation,Cleans user data
TransformOrders,Transformation,Cleans order data
JoinData,Transformation,Joins users and orders
AggregateMetrics,Transformation,Calculates daily metrics
LoadWarehouse,Load,Loads data into Redshift
NotifySuccess,Notification,Sends Slack alert
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
