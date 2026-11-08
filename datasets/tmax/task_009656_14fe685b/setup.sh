#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/config_events.txt
1620000000|alice|CREATE|Db.Host|localhost
1620000050|alice|UPDATE|Db.Port|5432
1620001800|bob|UPDATE|db.host|db.example.com
1620003600|charlie|UPDATE|API-KEY|secret123
1620003700|bob|UPDATE|api-key|secret123
1620005000|alice|UPDATE|API-KEY|super_secret
1620007200|bob|UPDATE|feature_flag_X|true
1620007210|bob|UPDATE|feature_flag_X|false
1620007220|bob|UPDATE|feature_flag_X|true
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
