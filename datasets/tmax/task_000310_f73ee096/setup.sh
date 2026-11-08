#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/incoming/loc_drops.csv
T001,es,1696118400,carlos@agency.com,120
T002,fr,1696118450,marie@paris.fr,200
T001,es,1696204800,carlos@agency.com,150
T003,de,1696204900,hans@berlin.de,90
T002,fr,1696204900,marie@paris.fr,200
T004,es,1696291200,luis@agency.com,300
T005,fr,1696291200,luc@paris.fr,110
T003,de,1696291500,hans@berlin.de,95
EOF

    chown -R user:user /home/user/incoming
    chown -R user:user /home/user/output

    chmod -R 777 /home/user
