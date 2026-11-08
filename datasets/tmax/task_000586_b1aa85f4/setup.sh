#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/graph_backup.nt
<http://example.org/server/AppServer> <http://example.org/vocab/dependsOn> <http://example.org/server/DB_Primary> .
<http://example.org/server/AppServer> <http://example.org/vocab/dependsOn> <http://example.org/server/Redis_Cache> .
<http://example.org/server/DB_Primary> <http://example.org/vocab/dependsOn> <http://example.org/server/Storage_SAN> .
<http://example.org/server/DB_Primary> <http://example.org/vocab/dependsOn> <http://example.org/server/AuthService> .
<http://example.org/server/AuthService> <http://example.org/vocab/dependsOn> <http://example.org/server/UserDB> .
EOF

    cat << 'EOF' > /home/user/run_sparql.py
import sys, argparse
import rdflib

parser = argparse.ArgumentParser()
parser.add_argument('--data', required=True)
parser.add_argument('--query', required=True)
args = parser.parse_args()

g = rdflib.Graph()
g.parse(args.data, format='nt')

with open(args.query, 'r') as f:
    q = f.read()

res = g.query(q)
print(res.serialize(format='json').decode('utf-8'))
EOF

    chmod -R 777 /home/user
