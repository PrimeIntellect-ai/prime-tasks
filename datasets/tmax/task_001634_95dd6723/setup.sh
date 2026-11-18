#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl libcurl4-openssl-dev wget tar
    pip3 install pytest flask requests

    # Setup cJSON
    mkdir -p /app
    cd /app
    wget https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz
    tar xzf v1.7.15.tar.gz
    rm v1.7.15.tar.gz
    mv cJSON-1.7.15 cjson-1.7.15
    cd cjson-1.7.15
    sed -i 's/CFLAGS/CFLGS/g' Makefile

    # Setup user
    useradd -m -s /bin/bash user || true

    # Setup corpus
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Clean 1: Valid resources, valid DAG
    cat << 'EOF' > /home/user/corpus/clean/pipe1.json
{"jobs": [{"name": "A", "cpu": 10, "mem": 20, "depends_on": []}, {"name": "B", "cpu": 20, "mem": 30, "depends_on": ["A"]}]}
EOF

    # Clean 2: Valid resources, valid DAG, complex
    cat << 'EOF' > /home/user/corpus/clean/pipe2.json
{"jobs": [{"name": "A", "cpu": 50, "mem": 100, "depends_on": []}, {"name": "B", "cpu": 50, "mem": 100, "depends_on": ["A"]}]}
EOF

    # Evil 1: Resource exhaustion (cpu > 100)
    cat << 'EOF' > /home/user/corpus/evil/pipe1.json
{"jobs": [{"name": "A", "cpu": 60, "mem": 20, "depends_on": []}, {"name": "B", "cpu": 50, "mem": 30, "depends_on": ["A"]}]}
EOF

    # Evil 2: Resource exhaustion (mem > 200)
    cat << 'EOF' > /home/user/corpus/evil/pipe2.json
{"jobs": [{"name": "A", "cpu": 10, "mem": 150, "depends_on": []}, {"name": "B", "cpu": 10, "mem": 60, "depends_on": ["A"]}]}
EOF

    # Evil 3: Cyclic dependency
    cat << 'EOF' > /home/user/corpus/evil/pipe3.json
{"jobs": [{"name": "A", "cpu": 10, "mem": 20, "depends_on": ["B"]}, {"name": "B", "cpu": 20, "mem": 30, "depends_on": ["A"]}]}
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
