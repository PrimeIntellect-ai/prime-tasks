#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest rdflib flask fastapi uvicorn requests

    mkdir -p /app

    cat << 'EOF' > /app/backup_topology.ttl
@prefix ex: <http://example.org/backup/> .

ex:alpha-10 ex:dependsOn ex:base-01 .
ex:beta-20 ex:dependsOn ex:alpha-10 .
ex:gamma-30 ex:dependsOn ex:beta-20 .
ex:delta-92 ex:dependsOn ex:gamma-30 .
ex:epsilon-93 ex:dependsOn ex:delta-92 .
ex:zeta-94 ex:dependsOn ex:epsilon-93 .
EOF

    espeak -w /app/incident_report.wav "The corruption was detected starting at backup snapshot delta dash ninety two."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
