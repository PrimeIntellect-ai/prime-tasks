#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar libyajl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/active_logs /home/user/backup_staging
    mkdir -p /app/ijson-3.2.3

    # Download and extract ijson 3.2.3
    wget -qO ijson.tar.gz https://files.pythonhosted.org/packages/source/i/ijson/ijson-3.2.3.tar.gz
    tar -xzf ijson.tar.gz -C /app/ijson-3.2.3 --strip-components=1
    rm ijson.tar.gz

    # Apply perturbation to disable the C extension by default
    sed -i 's/use_c_ext = True/use_c_ext = False/g' /app/ijson-3.2.3/setup.py

    # Ensure the perturbation is present in case the sed command didn't match
    if ! grep -q "use_c_ext = False" /app/ijson-3.2.3/setup.py; then
        echo "use_c_ext = False" >> /app/ijson-3.2.3/setup.py
    fi

    chown -R user:user /app/ijson-3.2.3
    chmod -R 777 /app/ijson-3.2.3
    chmod -R 777 /home/user
