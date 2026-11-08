#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/org_architecture.ttl
@prefix org: <http://example.org/ns#> .

org:Alice a org:User ;
    org:hasRole org:Developer ;
    org:hasAccess [
        org:targetResource org:Production_DB ;
        org:accessType "READ"
    ], [
        org:targetResource org:Test_DB ;
        org:accessType "WRITE"
    ] .

org:Bob a org:User ;
    org:hasRole org:Developer, org:Auditor ;
    org:hasAccess [
        org:targetResource org:Production_DB ;
        org:accessType "WRITE"
    ] .

org:Charlie a org:User ;
    org:hasRole org:Auditor ;
    org:hasAccess [
        org:targetResource org:Production_DB ;
        org:accessType "READ"
    ] .

org:Dave a org:User ;
    org:hasRole org:Developer ;
    org:hasAccess [
        org:targetResource org:Production_DB ;
        org:accessType "WRITE"
    ] .

org:Eve a org:User ;
    org:hasRole org:Admin ;
    org:hasAccess [
        org:targetResource org:Production_DB ;
        org:accessType "WRITE"
    ] .
EOF

    chmod -R 777 /home/user
