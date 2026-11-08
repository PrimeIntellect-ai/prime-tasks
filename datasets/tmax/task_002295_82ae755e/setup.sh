#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import json

os.makedirs('/home/user', exist_ok=True)

data = [
    {'pid': 'P_COMPLIANCE_AUDIT', 'held_locks': ['R_ALPHA'], 'waiting_for': ['R_BETA']},
    {'pid': 'P_UNRELATED', 'held_locks': ['R_OMEGA'], 'waiting_for': []},
    {'process_id': 'P_X1', 'state': {'has': ['R_BETA'], 'wants': ['R_GAMMA']}},
    {'process_id': 'P_X2', 'state': {'has': ['R_DELTA'], 'wants': ['R_EPSILON']}},
    {'proc': 'P_Y1', 'resources': {'locked': ['R_GAMMA'], 'requested': ['R_DELTA']}},
    {'proc': 'P_Y2', 'resources': {'locked': ['R_EPSILON'], 'requested': ['R_ALPHA']}},
    {'pid': 'P_NOISE1', 'held_locks': ['R_THETA'], 'waiting_for': ['R_BETA']},
    {'process_id': 'P_NOISE2', 'state': {'has': ['R_ZETA'], 'wants': ['R_THETA']}}
]

with open('/home/user/system_locks.jsonl', 'w') as f:
    for record in data:
        f.write(json.dumps(record) + '\n')
"

    chmod -R 777 /home/user
