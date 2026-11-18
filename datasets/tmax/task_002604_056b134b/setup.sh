#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/inventory.csv
ServerID,Hostname,OS,Notes,Status
101,WEB-front-01,ubuntu,"Primary web node",active
102,DB-master,centos,"Requires immediate attention
and restart",active
103,CACHE-01,debian,"Redis cluster node",inactive
101,web-front-01,Ubuntu,"Primary web node, upgraded",active
104,API-gw,rhel,"API Gateway
v2.0 deployment
do not reboot",active
105,WORKER-node,Alpine,"Background jobs",inactive
106,LB-01,haproxy,"Load balancer",active
105,worker-node,alpine,"Background jobs (migrated)",active
107,Metrics-01,Ubuntu,"Prometheus
Grafana",inactive
EOF

chmod -R 777 /home/user
