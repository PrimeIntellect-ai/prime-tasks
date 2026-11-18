#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/hub_transit_data.csv
source_hub,destination_hub,transit_time
Seattle,Denver,10
Denver,Chicago,5
Seattle,Chicago,20
Chicago,NewYork,10
Denver,NewYork,20
NewYork,Miami,5
Seattle,SanFrancisco,8
SanFrancisco,LosAngeles,6
LosAngeles,Miami,25
Chicago,Dallas,12
Dallas,Miami,8
EOF

    chmod -R 777 /home/user
