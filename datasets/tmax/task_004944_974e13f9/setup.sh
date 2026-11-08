#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make wget tar
    pip3 install pytest

    # Create app directory and download cJSON
    mkdir -p /app
    cd /app
    wget https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz
    tar -xzf v1.7.15.tar.gz
    rm v1.7.15.tar.gz

    # Introduce the perturbation in the Makefile
    sed -i '12i CC = broken-gcc' /app/cJSON-1.7.15/Makefile

    # Create corpora directories
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Populate clean corpus
    cat << 'EOF' > /home/user/corpora/clean/clean1.csv
q1,users,[{"$match":{"status":"A"}}]
q2,orgs,[{"$graphLookup":{"from":"orgs","startWith":"$parent","connectFromField":"parent","connectToField":"id","as":"hierarchy","maxDepth":3}}]
q3,nodes,[{"$project":{"id":1}},{"$graphLookup":{"from":"nodes","maxDepth":5}}]
q4,files,[{"$graphLookup":{"maxDepth":0}}]
EOF

    # Populate evil corpus
    cat << 'EOF' > /home/user/corpora/evil/evil1.csv
q5,orgs,[{"$graphLookup":{"from":"orgs","startWith":"$parent","connectFromField":"parent","connectToField":"id","as":"hierarchy"}}]
q6,nodes,[{"$graphLookup":{"from":"nodes","maxDepth":6}}]
q7,nodes,[{"$graphLookup":{"from":"nodes","maxDepth":-1}}]
q8,files,[{"$graphLookup":{"from":"files","maxDepth":9999}}]
EOF

    # Create user and fix permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
