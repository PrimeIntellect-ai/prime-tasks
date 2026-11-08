#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    cat << 'EOF' > /home/user/incoming/day1.dat
2023-11-01|Hello world!|Nothing to report.|Critical error on DB.
2023-11-02|All systems go.|Running smoothly.|Wait, what?
EOF

    cat << 'EOF' > /home/user/incoming/day2.dat
2023-11-03|Fast network today.|Latency spike; fixed.|Normal operations.
EOF

    cat << 'EOF' > /home/user/incoming/day3.dat
2023-11-04|Testing 1 2 3.|Alpha beta gamma.|Omega... done!
EOF

    chown -R user:user /home/user/incoming
    chmod -R 777 /home/user
