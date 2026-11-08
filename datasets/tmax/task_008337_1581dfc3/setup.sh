#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/company_data.ttl
@prefix ex: <http://example.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

ex:Alice a ex:Employee ;
    foaf:name "Alice Smith" ;
    ex:worksOn ex:Project1, ex:Project2, ex:Project3 .

ex:Bob a ex:Employee ;
    foaf:name "Bob Jones" ;
    ex:worksOn ex:Project1 .

ex:Charlie a ex:Employee ;
    foaf:name "Charlie Brown" ;
    ex:worksOn ex:Project2, ex:Project4 .

ex:Diana a ex:Employee ;
    foaf:name "Diana Prince" ;
    ex:worksOn ex:Project1, ex:Project2, ex:Project3, ex:Project4 .

ex:Eve a ex:Employee ;
    foaf:name "Eve Davis" ;
    ex:worksOn ex:Project1, ex:Project5 .

ex:Frank a ex:Employee ;
    foaf:name "Frank Miller" ;
    ex:worksOn ex:Project5, ex:Project6, ex:Project7 .
EOF

    chmod -R 777 /home/user
