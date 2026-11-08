#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/signals

    cat << 'EOF' > /home/user/signals/signal_1.dat
100 0.0
200 1.0
300 50.0
400 500.0
EOF

    cat << 'EOF' > /home/user/signals/signal_2.dat
100 0.1
200 50.0
300 150.0
EOF

    cat << 'EOF' > /home/user/signals/signal_3.dat
100 0.0
200 2.0
300 1000.0
400 2500.0
EOF

    cat << 'EOF' > /home/user/signals/signal_4.dat
100 5.0
200 7.5
300 10.0
EOF

    cat << 'EOF' > /home/user/signals/signal_5.dat
100 0.001
200 0.5
300 1.001
EOF

    chown -R user:user /home/user/signals
    chmod -R 777 /home/user
