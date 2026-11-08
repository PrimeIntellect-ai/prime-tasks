#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq binutils coreutils grep gawk
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > service_a.log
{"timestamp": "2023-10-27T08:12:01Z", "service": "Python-A", "tx_id": "tx-8081", "amount": 150.0}
{"timestamp": "2023-10-27T08:14:22Z", "service": "Python-A", "tx_id": "tx-8082", "amount": 1024.99}
{"timestamp": "2023-10-27T08:15:45Z", "service": "Python-A", "tx_id": "tx-8083", "amount": 333.3333333333333}
{"timestamp": "2023-10-27T08:19:10Z", "service": "Python-A", "tx_id": "tx-8084", "amount": 500.5}
EOF

    head -c 1024 /dev/urandom > service_b_dump.bin
    echo '{"timestamp": "2023-10-27T08:12:03Z", "service": "Node-B", "tx_id": "tx-8081", "amount": 150}' >> service_b_dump.bin
    head -c 512 /dev/urandom >> service_b_dump.bin
    echo '{"timestamp": "2023-10-27T08:14:24Z", "service": "Node-B", "tx_id": "tx-8082", "amount": 1024.99}' >> service_b_dump.bin
    head -c 2048 /dev/urandom >> service_b_dump.bin
    echo '{"timestamp": "2023-10-27T08:15:48Z", "service": "Node-B", "tx_id": "tx-8083", "amount": 333.333}' >> service_b_dump.bin
    head -c 128 /dev/urandom >> service_b_dump.bin
    echo '{"timestamp": "2023-10-27T08:19:12Z", "service": "Node-B", "tx_id": "tx-8084", "amount": 500.5}' >> service_b_dump.bin
    head -c 1024 /dev/urandom >> service_b_dump.bin

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
