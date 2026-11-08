#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil /app/incoming_configs /home/user

    # Download and extract dictdiffer 0.9.0
    cd /tmp
    pip3 download --no-binary :all: --no-deps dictdiffer==0.9.0
    tar -xzf dictdiffer-0.9.0.tar.gz -C /app
    rm dictdiffer-0.9.0.tar.gz

    # Inject perturbation
    sed -i '14i raise ImportError("Missing required dependency: dummy_dep")' /app/dictdiffer-0.9.0/dictdiffer/__init__.py

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/clean_1.json
{"server_id": "srv1", "timestamp": 100, "pre_install": "echo starting", "file_path": "/etc/app_config/main.conf", "env": {"PORT": "8080"}}
EOF

    cat << 'EOF' > /app/corpora/clean/clean_2.json
{"server_id": "srv2", "timestamp": 105, "post_install": "systemctl restart app", "file_path": "/etc/app_config/db.conf", "env": {}}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/evil_1.json
{"server_id": "srv3", "pre_install": "/bin/sh -c 'rm -rf /'", "file_path": "/etc/app_config/main.conf", "env": {}}
EOF

    cat << 'EOF' > /app/corpora/evil/evil_2.json
{"server_id": "srv4", "pre_install": "echo", "file_path": "/etc/shadow", "env": {}}
EOF

    cat << 'EOF' > /app/corpora/evil/evil_3.json
{"server_id": "srv5", "pre_install": "echo", "file_path": "/etc/app_config/main.conf", "env": {"LD_PRELOAD": "./malicious.so"}}
EOF

    # Create baseline
    cat << 'EOF' > /app/baseline.json
{"server_id": "baseline", "timestamp": 0, "pre_install": "none", "file_path": "/etc/app_config/main.conf", "env": {}}
EOF

    # Populate incoming configs
    cp /app/corpora/clean/clean_1.json /app/incoming_configs/inc_clean_1.json
    cp /app/corpora/clean/clean_2.json /app/incoming_configs/inc_clean_2.json
    cp /app/corpora/evil/evil_1.json /app/incoming_configs/inc_evil_1.json
    cp /app/corpora/evil/evil_2.json /app/incoming_configs/inc_evil_2.json

    # Add a duplicate for srv1 with a higher timestamp
    cat << 'EOF' > /app/incoming_configs/inc_clean_1_dup.json
{"server_id": "srv1", "timestamp": 110, "pre_install": "echo updated", "file_path": "/etc/app_config/main.conf", "env": {"PORT": "8081"}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
