#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest rdflib networkx

mkdir -p /home/user

cat << 'EOF' > /home/user/citation_graph.nt
<http://example.org/paper/P1> <http://example.org/ontology/cites> <http://example.org/paper/P2> .
<http://example.org/paper/P1> <http://example.org/ontology/cites> <http://example.org/paper/P3> .
<http://example.org/paper/P2> <http://example.org/ontology/cites> <http://example.org/paper/P4> .
<http://example.org/paper/P3> <http://example.org/ontology/cites> <http://example.org/paper/P6> .
<http://example.org/paper/P4> <http://example.org/ontology/cites> <http://example.org/paper/P5> .
<http://example.org/paper/P6> <http://example.org/ontology/cites> <http://example.org/paper/P8> .
<http://example.org/paper/P5> <http://example.org/ontology/cites> <http://example.org/paper/P8> .
<http://example.org/paper/P8> <http://example.org/ontology/cites> <http://example.org/paper/P9> .

<http://example.org/paper/P1> <http://example.org/ontology/authoredBy> <http://example.org/author/A1> .
<http://example.org/paper/P2> <http://example.org/ontology/authoredBy> <http://example.org/author/A1> .

<http://example.org/paper/P3> <http://example.org/ontology/authoredBy> <http://example.org/author/A2> .

<http://example.org/paper/P4> <http://example.org/ontology/authoredBy> <http://example.org/author/A3> .
<http://example.org/paper/P5> <http://example.org/ontology/authoredBy> <http://example.org/author/A3> .
<http://example.org/paper/P6> <http://example.org/ontology/authoredBy> <http://example.org/author/A3> .
<http://example.org/paper/P7> <http://example.org/ontology/authoredBy> <http://example.org/author/A3> .

<http://example.org/paper/P8> <http://example.org/ontology/authoredBy> <http://example.org/author/A4> .
<http://example.org/paper/P9> <http://example.org/ontology/authoredBy> <http://example.org/author/A4> .
<http://example.org/paper/P10> <http://example.org/ontology/authoredBy> <http://example.org/author/A4> .
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
