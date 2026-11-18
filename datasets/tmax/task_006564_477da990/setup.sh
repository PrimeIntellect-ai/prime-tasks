#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/org.ttl
@prefix ex: <http://example.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

ex:DeptA a ex:Department ; foaf:name "Analytics" .
ex:DeptB a ex:Department ; foaf:name "Engineering" .
ex:DeptC a ex:Department ; foaf:name "Sales" .
ex:DeptD a ex:Department ; foaf:name "HR" .

ex:Alice a ex:Employee ;
    foaf:name "Alice" ;
    ex:worksIn ex:DeptA ;
    ex:tenure 12 ;
    ex:manages ex:Bob, ex:Charlie .

ex:Bob a ex:Employee ;
    foaf:name "Bob" ;
    ex:worksIn ex:DeptA ;
    ex:tenure 5 ;
    ex:manages ex:Dave .

ex:Charlie a ex:Employee ;
    foaf:name "Charlie" ;
    ex:worksIn ex:DeptA ;
    ex:tenure 2 .

ex:Eve a ex:Employee ;
    foaf:name "Eve" ;
    ex:worksIn ex:DeptB ;
    ex:tenure 8 ;
    ex:manages ex:Frank, ex:Grace, ex:Heidi .

ex:Ivan a ex:Employee ;
    foaf:name "Ivan" ;
    ex:worksIn ex:DeptC ;
    ex:tenure 16 ;
    ex:manages ex:Judy, ex:Karl .

ex:Judy a ex:Employee ;
    foaf:name "Judy" ;
    ex:worksIn ex:DeptC ;
    ex:tenure 4 ;
    ex:manages ex:Leo, ex:Mia .

ex:Oscar a ex:Employee ;
    foaf:name "Oscar" ;
    ex:worksIn ex:DeptD ;
    ex:tenure 15 ;
    ex:manages ex:Paul, ex:Quinn, ex:Rita .
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
