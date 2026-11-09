#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access_graph.ttl
@prefix ex: <http://example.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

ex:emp1 a ex:Employee ;
    foaf:name "Alice Smith" ;
    ex:department "Engineering" ;
    ex:hasAccessTo ex:FinancialSystem, ex:HRSystem, ex:DevSystem .

ex:emp2 a ex:Employee ;
    foaf:name "Bob Johnson" ;
    ex:department "Executive" ;
    ex:hasAccessTo ex:FinancialSystem, ex:HRSystem .

ex:emp3 a ex:Employee ;
    foaf:name "Charlie Davis" ;
    ex:department "HR" ;
    ex:hasAccessTo ex:HRSystem .

ex:emp4 a ex:Employee ;
    foaf:name "Dave Wilson" ;
    ex:department "Finance" ;
    ex:hasAccessTo ex:FinancialSystem .

ex:emp5 a ex:Employee ;
    foaf:name "Eve Brown" ;
    ex:department "IT" ;
    ex:hasAccessTo ex:FinancialSystem, ex:HRSystem, ex:AdminSystem .

ex:FinancialSystem a ex:System .
ex:HRSystem a ex:System .
ex:DevSystem a ex:System .
ex:AdminSystem a ex:System .
EOF

    chmod -R 777 /home/user
