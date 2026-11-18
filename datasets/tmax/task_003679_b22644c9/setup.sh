#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/system_metrics.log
1700000000 45 3000
1700000010 50 3300
1700000010 50 3300
1700000020 40 2000
1700000030 20 1500
1700000040 25 1000
1700000040 25 1000
1700000040 25 1000
1700000050 15 800
1700000060 60 4000
EOF

    cat << 'EOF' > /home/user/calculate_cooling.awk
{
    cooling_factor = $3 / ($2 - 20)
    print $1, cooling_factor
}
EOF

    chmod +x /home/user/calculate_cooling.awk
    chmod -R 777 /home/user
