#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        redis-tools \
        libhiredis-dev \
        nlohmann-json3-dev \
        g++

    pip3 install pytest redis

    mkdir -p /app

    # Create dummy files to satisfy initial state tests
    touch /app/init_redis.py
    touch /app/generator.py
    touch /app/sink.py
    touch /app/test_e2e.sh

    # Create a dummy executable for oracle_processor
    echo '#!/bin/bash' > /app/oracle_processor
    chmod +x /app/oracle_processor
    chmod +x /app/test_e2e.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
