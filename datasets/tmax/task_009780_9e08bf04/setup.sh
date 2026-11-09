#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.ttl
@prefix org: <http://example.org/org#> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

org:Corp a org:Department ;
    foaf:name "Corporation" .

org:Engineering a org:Department ;
    foaf:name "Engineering" ;
    org:parentDept org:Corp .

org:Backend a org:Department ;
    foaf:name "Backend" ;
    org:parentDept org:Engineering .

org:Frontend a org:Department ;
    foaf:name "Frontend" ;
    org:parentDept org:Engineering .

org:Sales a org:Department ;
    foaf:name "Sales" ;
    org:parentDept org:Corp .

org:EnterpriseSales a org:Department ;
    foaf:name "Enterprise Sales" ;
    org:parentDept org:Sales .

org:Alice a foaf:Person ;
    foaf:name "Alice" ;
    org:worksIn org:Backend .

org:Bob a foaf:Person ;
    foaf:name "Bob" ;
    org:worksIn org:Frontend .

org:Charlie a foaf:Person ;
    foaf:name "Charlie" ;
    org:worksIn org:Sales .

org:Dave a foaf:Person ;
    foaf:name "Dave" ;
    org:worksIn org:Engineering .

org:Eve a foaf:Person ;
    foaf:name "Eve" ;
    org:worksIn org:EnterpriseSales .
EOF

    chmod -R 777 /home/user
