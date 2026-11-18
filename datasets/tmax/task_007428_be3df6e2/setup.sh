#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/corporate_graph.ttl
@prefix ex: <http://example.org/audit/> .

ex:ShellA ex:owns ex:ShellB .
ex:ShellB ex:owns ex:ShellC .
ex:ShellC ex:transactsWith ex:ShellA .

ex:LegitA ex:owns ex:LegitB .
ex:LegitB ex:owns ex:LegitC .
ex:LegitC ex:transactsWith ex:LegitD .

ex:FraudX ex:owns ex:FraudY .
ex:FraudY ex:owns ex:FraudZ .
ex:FraudZ ex:transactsWith ex:FraudX .

ex:Loop1 ex:transactsWith ex:Loop2 .
ex:Loop2 ex:transactsWith ex:Loop3 .
ex:Loop3 ex:transactsWith ex:Loop1 .
EOF

    chmod -R 777 /home/user
