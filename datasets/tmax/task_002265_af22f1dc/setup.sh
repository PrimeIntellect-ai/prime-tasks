#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib networkx

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/dataset.nt
<http://example.org/res/1> <http://xmlns.com/foaf/0.1/name> "Dr. Alice" .
<http://example.org/res/2> <http://xmlns.com/foaf/0.1/name> "Dr. Bob" .
<http://example.org/res/3> <http://xmlns.com/foaf/0.1/name> "Dr. Charlie" .
<http://example.org/res/4> <http://xmlns.com/foaf/0.1/name> "Dr. Delta" .
<http://example.org/res/5> <http://xmlns.com/foaf/0.1/name> "Dr. Zeta" .
<http://example.org/res/6> <http://xmlns.com/foaf/0.1/name> "Dr. Echo" .

<http://example.org/res/1> <http://example.org/ontology/collaboratesWith> <http://example.org/res/2> .
<http://example.org/res/1> <http://example.org/ontology/collaboratesWith> <http://example.org/res/3> .
<http://example.org/res/2> <http://example.org/ontology/collaboratesWith> <http://example.org/res/4> .
<http://example.org/res/3> <http://example.org/ontology/collaboratesWith> <http://example.org/res/6> .
<http://example.org/res/4> <http://example.org/ontology/collaboratesWith> <http://example.org/res/5> .
<http://example.org/res/6> <http://example.org/ontology/collaboratesWith> <http://example.org/res/5> .
EOF

    chmod -R 777 /home/user
