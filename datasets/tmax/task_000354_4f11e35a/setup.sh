#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo curl build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.nt
<http://example.org/paper/1> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Paper> .
<http://example.org/paper/1> <http://example.org/title> "Graph Processing in Rust" .
<http://example.org/paper/1> <http://example.org/author> <http://example.org/person/A> .
<http://example.org/person/A> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Researcher> .
<http://example.org/person/A> <http://example.org/name> "Alice" .
<http://example.org/person/A> <http://example.org/worksAt> <http://example.org/org/1> .
<http://example.org/org/1> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Institution> .
<http://example.org/org/1> <http://example.org/orgName> "University of Graph" .
<http://example.org/paper/2> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Paper> .
<http://example.org/paper/2> <http://example.org/year> "2023"^^<http://www.w3.org/2001/XMLSchema#integer> .
<http://example.org/paper/2> <http://example.org/author> <http://example.org/person/B> .
<http://example.org/person/B> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Researcher> .
<http://example.org/person/B> <http://example.org/name> "Bob" .
EOF

    chmod -R 777 /home/user
