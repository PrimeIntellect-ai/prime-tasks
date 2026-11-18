#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ coreutils gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/incoming
    mkdir -p /home/user/dataset/chunks
    mkdir -p /home/user/dataset/archive

    cat << 'EOF' > /home/user/simulate_stream.sh
#!/bin/bash
# Simulate data collection
dd if=/dev/urandom of=/home/user/dataset/incoming/dataset_A.dat bs=1 count=250000 status=none
touch /home/user/dataset/incoming/dataset_A.ready
sleep 1
dd if=/dev/urandom of=/home/user/dataset/incoming/dataset_B.dat bs=1 count=80000 status=none
touch /home/user/dataset/incoming/dataset_B.ready
sleep 1
touch /home/user/dataset/incoming/DONE.ready
EOF
    chmod +x /home/user/simulate_stream.sh

    chmod -R 777 /home/user
