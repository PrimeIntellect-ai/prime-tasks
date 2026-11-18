#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_experiments.log
experiment_id|model_name|successes|trials|exec_time_sec
EXP01|ModelX|800|1000|45
EXP02|ModelY|450|500|-10
EXP03|ModelX|900||120
EXP04|ModelZ|1100|1000|50
EXP05|ModelY|400|500|60
EXP06|ModelZ|20|100|9999
EXP07|ModelY|100|200|30
EXP08|ModelX||1000|40
EOF

    chmod 644 /home/user/raw_experiments.log
    chmod -R 777 /home/user
