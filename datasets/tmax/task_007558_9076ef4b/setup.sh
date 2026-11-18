#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/experiments.log
--- BEGIN RUN ---
Timestamp: 2023-10-01T12:00:00Z
RunID: 1042
User: jsmith
Parameters:
  alpha=0.5
  beta=1.2
    gamma=3.0
Results: SUCCESS
--- END RUN ---
--- BEGIN RUN ---
Timestamp: 2023-10-02T14:30:00Z
RunID: 1043
User: alice_w
Parameters:
model=transformer
 layers=12
Results: FAILURE
--- END RUN ---
--- BEGIN RUN ---
Timestamp: 2023-10-03T09:15:00Z
RunID: 1044
User: bob_jones
Parameters:
Results: SUCCESS
--- END RUN ---
EOF

    chmod -R 777 /home/user
