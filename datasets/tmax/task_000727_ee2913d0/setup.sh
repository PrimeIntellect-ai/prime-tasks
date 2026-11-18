#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
2023-10-15T14:23:01,alpha_sensor,10.5
2023-10-15T14:23:01,alpha_sensor,10.5
2023-10-15T14:45:10,alpa_sensor,12.5
2023-10-15T15:05:00,beta_sensor,20.0
2023-10-15T15:10:00,bet_sensor,22.0
2023-10-15T15:10:00,unknown_thing,100.0
2023-10-15T16:00:00,gamma_sensor,5.0
2023-10-15T16:01:00,gama_sensor,7.0
2023-10-15T16:01:00,gama_sensor,7.0
invalid_line_no_regex_match
EOF

    chmod -R 777 /home/user
