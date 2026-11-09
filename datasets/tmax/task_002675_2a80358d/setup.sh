#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y redis-server nginx gcc make libc6-dev libhiredis-dev curl

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create dummy corpus files
    echo "a1b2c3d4e5f6g7h8,1678886400,Hello World,42.5" > /app/corpus/clean/clean_1.csv
    echo "invalid_id,1678886400,Hello World,42.5" > /app/corpus/evil/evil_1.csv

    # Setup www directory
    mkdir -p /home/user/www

    # Create user
    useradd -m -s /bin/bash user || true

    # Create a wrapper for pytest to start redis-server before tests run
    mv /usr/local/bin/pytest /usr/local/bin/pytest_orig
    cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
redis-server --daemonize yes
sleep 1
/usr/local/bin/pytest_orig "$@"
EOF
    chmod +x /usr/local/bin/pytest

    chmod -R 777 /home/user
    chmod -R 777 /app
