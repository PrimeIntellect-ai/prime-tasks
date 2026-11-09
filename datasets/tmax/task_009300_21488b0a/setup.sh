#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib networkx

    mkdir -p /home/user
    cat << 'EOF' > /home/user/access_graph.ttl
@prefix ex: <http://example.org/audit#> .

ex:User1 ex:accessed ex:SystemA, ex:SystemB, ex:SystemC .
ex:User2 ex:accessed ex:SystemA, ex:SystemC .
ex:User3 ex:accessed ex:SystemC, ex:SystemD .
ex:User4 ex:accessed ex:SystemA, ex:SystemC, ex:SystemE .
ex:User5 ex:accessed ex:SystemB, ex:SystemC .
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
