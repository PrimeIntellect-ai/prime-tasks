#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk grep sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import random
import csv

random.seed(42)

roles = ['web_server', 'db_node', 'cache']
base_configs = {
    'web_server': {'timeout': [30, 60], 'max_connections': [100, 150, 200, 50, 500], 'ssl': ['true', 'false']},
    'db_node': {'max_connections': [1000, 2000], 'retry': [3, 5]},
    'cache': {'max_connections': [5000], 'eviction': ['lru']}
}

weights = {
    'web_server': [0.5, 0.3, 0.1, 0.08, 0.02], # weights for max_connections
    'db_node': [0.7, 0.3],
    'cache': [1.0]
}

def mess_up_string(s):
    spaces_before = " " * random.randint(0, 3)
    spaces_after = " " * random.randint(0, 3)
    casing = random.choice([s.lower(), s.upper(), s.capitalize()])
    return f"{spaces_before}{casing}{spaces_after}"

with open('/home/user/config_changes.csv', 'w') as f:
    # 2000 records
    for i in range(2000):
        role = random.choices(roles, weights=[0.6, 0.3, 0.1])[0]

        config_pairs = []
        for k, v_list in base_configs[role].items():
            if k == 'max_connections':
                val = random.choices(v_list, weights=weights[role])[0]
            else:
                val = random.choice(v_list)

            k_str = mess_up_string(k)
            v_str = mess_up_string(str(val))
            config_pairs.append(f"{k_str}:{v_str}")

        random.shuffle(config_pairs)
        config_data = ";".join(config_pairs)

        server_id = f"srv-{i:04d}"
        f.write(f"2023-10-01 12:00:00 | {server_id} | {role} | {config_data}\n")
EOF
    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
