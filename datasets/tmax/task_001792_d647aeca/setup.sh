#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ownership_data.json
[
  {"entity_id": "E1", "owns": [{"target_id": "E2", "percentage": 30}]},
  {"entity_id": "E2", "owns": [{"target_id": "E3", "percentage": 40}]},
  {"entity_id": "E3", "owns": [{"target_id": "E1", "percentage": 50}, {"target_id": "E4", "percentage": 26}]},
  {"entity_id": "E4", "owns": [{"target_id": "E5", "percentage": 30}]},
  {"entity_id": "E5", "owns": [{"target_id": "E3", "percentage": 30}, {"target_id": "E6", "percentage": 20}]},
  {"entity_id": "E6", "owns": [{"target_id": "E7", "percentage": 30}]},
  {"entity_id": "E7", "owns": [{"target_id": "E5", "percentage": 30}]},
  {"entity_id": "E8", "owns": [{"target_id": "E9", "percentage": 50}]},
  {"entity_id": "E9", "owns": [{"target_id": "E10", "percentage": 50}]},
  {"entity_id": "E10", "owns": [{"target_id": "E8", "percentage": 50}, {"target_id": "E11", "percentage": 60}]},
  {"entity_id": "E11", "owns": [{"target_id": "E12", "percentage": 60}]},
  {"entity_id": "E12", "owns": [{"target_id": "E10", "percentage": 60}]},
  {"entity_id": "E13", "owns": [{"target_id": "E14", "percentage": 90}]},
  {"entity_id": "E14", "owns": [{"target_id": "E15", "percentage": 90}]},
  {"entity_id": "E15", "owns": [{"target_id": "E13", "percentage": 90}]},
  {"entity_id": "E16", "owns": [{"target_id": "E17", "percentage": 30}]},
  {"entity_id": "E17", "owns": [{"target_id": "E18", "percentage": 30}]},
  {"entity_id": "E18", "owns": [{"target_id": "E16", "percentage": 30}]},
  {"entity_id": "E19", "owns": [{"target_id": "E20", "percentage": 30}]},
  {"entity_id": "E20", "owns": [{"target_id": "E21", "percentage": 30}]},
  {"entity_id": "E21", "owns": [{"target_id": "E19", "percentage": 30}]},
  {"entity_id": "E22", "owns": [{"target_id": "E23", "percentage": 30}]},
  {"entity_id": "E23", "owns": [{"target_id": "E24", "percentage": 30}]},
  {"entity_id": "E24", "owns": [{"target_id": "E22", "percentage": 30}]},
  {"entity_id": "E25", "owns": [{"target_id": "E26", "percentage": 30}]},
  {"entity_id": "E26", "owns": [{"target_id": "E27", "percentage": 30}]},
  {"entity_id": "E27", "owns": [{"target_id": "E25", "percentage": 30}]}
]
EOF

    chmod -R 777 /home/user
