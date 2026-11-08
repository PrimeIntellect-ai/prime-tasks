#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/events.jsonl
{"user_id": "U1", "item_id": "Item_A", "event_type": "purchase", "timestamp": "1000"}
{"user_id": "U1", "item_id": "Item_B", "event_type": "purchase", "timestamp": "1001"}
{"user_id": "U1", "item_id": "Item_C", "event_type": "purchase", "timestamp": "1002"}
{"user_id": "U2", "item_id": "Item_A", "event_type": "purchase", "timestamp": "1003"}
{"user_id": "U2", "item_id": "Item_B", "event_type": "purchase", "timestamp": "1004"}
{"user_id": "U3", "item_id": "Item_A", "event_type": "purchase", "timestamp": "1005"}
{"user_id": "U3", "item_id": "Item_D", "event_type": "purchase", "timestamp": "1006"}
{"user_id": "U3", "item_id": "Item_E", "event_type": "purchase", "timestamp": "1007"}
{"user_id": "U4", "item_id": "Item_B", "event_type": "purchase", "timestamp": "1008"}
{"user_id": "U4", "item_id": "Item_C", "event_type": "purchase", "timestamp": "1009"}
{"user_id": "U4", "item_id": "Item_F", "event_type": "purchase", "timestamp": "1010"}
{"user_id": "U5", "item_id": "Item_A", "event_type": "purchase", "timestamp": "1011"}
{"user_id": "U5", "item_id": "Item_B", "event_type": "purchase", "timestamp": "1012"}
{"user_id": "U5", "item_id": "Item_C", "event_type": "purchase", "timestamp": "1013"}
{"user_id": "U5", "item_id": "Item_D", "event_type": "purchase", "timestamp": "1014"}
{"user_id": "U6", "item_id": "Item_A", "event_type": "view", "timestamp": "1015"}
{"user_id": "U6", "item_id": "Item_Z", "event_type": "view", "timestamp": "1016"}
EOF

    chmod -R 777 /home/user
