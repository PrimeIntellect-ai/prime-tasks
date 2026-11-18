#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
node_id,department,account_status
1,Engineering,active
2,Engineering,active
3,Marketing,inactive
4,Sales,inactive
5,Finance,active
6,Finance,active
7,HR,inactive
8,Engineering,inactive
9,Finance,inactive
10,Engineering,active
EOF

    cat << 'EOF' > /home/user/edges.csv
source_id,target_id,message_size,timestamp
1,3,40,2023-10-01T10:00:00
3,5,30,2023-10-01T10:05:00
2,4,20,2023-10-01T10:10:00
4,6,60,2023-10-01T10:15:00
10,7,50,2023-10-02T11:00:00
7,5,10,2023-10-02T11:05:00
2,8,30,2023-10-03T09:00:00
8,6,35,2023-10-03T09:30:00
1,9,80,2023-10-04T14:00:00
9,5,20,2023-10-04T14:15:00
2,4,10,2023-10-05T08:00:00
4,5,45,2023-10-05T08:10:00
EOF

    cat << 'EOF' > /home/user/expected_results.csv
start_node,end_node,total_size,latest_timestamp
2,5,65,2023-10-05T08:10:00
2,5,55,2023-10-05T08:10:00
1,5,100,2023-10-04T14:15:00
2,6,65,2023-10-03T09:30:00
10,5,60,2023-10-02T11:05:00
EOF

    chmod -R 777 /home/user
