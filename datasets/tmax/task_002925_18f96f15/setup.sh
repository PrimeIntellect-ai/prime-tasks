#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask rdflib fastapi uvicorn

    useradd -m -s /bin/bash user || true

    # Create datasets.ttl
    cat << 'EOF' > /home/user/datasets.ttl
@prefix dc: <http://purl.org/dc/terms/> .
@prefix ex: <http://example.org/> .

ex:datasetA dc:creator ex:researcher1 ;
            dc:subject ex:domain1 .
ex:datasetB dc:creator ex:researcher1 ;
            dc:subject ex:domain1 .
ex:datasetC dc:creator ex:researcher2 ;
            dc:subject ex:domain1 .
EOF

    # Create /app/dataset_hasher
    mkdir -p /app
    cat << 'EOF' > /app/dataset_hasher
#!/usr/bin/env python3
import sys
import hashlib

lines = [line.strip() for line in sys.stdin.read().splitlines() if line.strip()]
joined = "|".join(lines)
print(hashlib.md5(joined.encode('utf-8')).hexdigest())
EOF
    chmod +x /app/dataset_hasher

    chmod -R 777 /home/user
