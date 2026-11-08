#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /var/tmp/etl_drop
    mkdir -p /home/user/workspace

    cat << 'EOF' > /var/tmp/etl_drop/server_metrics.log
[2023-10-14 10:00:05] INFO [MetricAgent] CPU_USAGE=10.0% Memory=1024MB
[2023-10-14 10:01:10] INFO [MetricAgent] CPU_USAGE=20.0% Memory=1024MB
[2023-10-14 10:01:45] INFO [MetricAgent] CPU_USAGE=30.0% Memory=1024MB
[2023-10-14 10:03:00] INFO [MetricAgent] CPU_USAGE=40.0% Memory=1024MB
[2023-10-14 10:01:45] INFO [MetricAgent] CPU_USAGE=30.0% Memory=1024MB
[2023-10-14 10:03:00] INFO [MetricAgent] CPU_USAGE=40.0% Memory=1024MB
[2023-10-14 10:04:15] INFO [MetricAgent] CPU_USAGE=50.0% Memory=1024MB
[2023-10-14 10:07:30] INFO [MetricAgent] CPU_USAGE=60.0% Memory=1024MB
[2023-10-14 10:08:12] INFO [MetricAgent] CPU_USAGE=70.0% Memory=1024MB
[2023-10-14 10:09:59] INFO [MetricAgent] CPU_USAGE=80.0% Memory=1024MB
[2023-10-14 10:00:05] INFO [MetricAgent] CPU_USAGE=10.0% Memory=1024MB
[2023-10-14 10:10:01] INFO [MetricAgent] CPU_USAGE=90.0% Memory=1024MB
EOF

    chmod 777 /var/tmp/etl_drop
    chmod 644 /var/tmp/etl_drop/server_metrics.log

    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
