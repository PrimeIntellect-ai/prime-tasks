#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/security_graph.ttl
@prefix ex: <http://example.org/sec#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

ex:Server_Alpha ex:hasVuln ex:CVE-2024-1111 ;
                ex:hasPatch ex:Patch_101 .
ex:Patch_101 ex:fixes ex:CVE-2024-1111 ;
             ex:status "Superseded" .

ex:Server_Beta ex:hasVuln ex:CVE-2024-1111 ;
               ex:hasPatch ex:Patch_102 .
ex:Patch_102 ex:fixes ex:CVE-2024-1111 ;
             ex:status "Active" .

ex:Server_Gamma ex:hasVuln ex:CVE-2024-1111 .

ex:Server_Delta ex:hasVuln ex:CVE-2024-1111 ;
                ex:hasPatch ex:Patch_103 , ex:Patch_104 .
ex:Patch_103 ex:fixes ex:CVE-2024-1111 ;
             ex:status "Superseded" .
ex:Patch_104 ex:fixes ex:CVE-2024-1111 ;
             ex:status "Revoked" .

ex:Server_Epsilon ex:hasVuln ex:CVE-2024-2222 ;
                  ex:hasPatch ex:Patch_201 .
ex:Patch_201 ex:fixes ex:CVE-2024-2222 ;
             ex:status "Active" .
EOF

    chmod -R 777 /home/user
