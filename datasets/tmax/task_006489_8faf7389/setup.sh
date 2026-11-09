#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/access_graph.ttl
@prefix ex: <http://example.org/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

ex:Emp1 a ex:Employee ;
    ex:name "Alice" ;
    ex:department "Finance" .

ex:Emp2 a ex:Employee ;
    ex:name "Bob" ;
    ex:department "Finance" .

ex:Emp3 a ex:Employee ;
    ex:name "Charlie" ;
    ex:department "Engineering" .

ex:Event1 a ex:AccessEvent ;
    ex:accessedBy ex:Emp1 ;
    ex:accessedResource ex:Resource_ProjectX ;
    ex:accessHour 19 .

ex:Event2 a ex:AccessEvent ;
    ex:accessedBy ex:Emp1 ;
    ex:accessedResource ex:Resource_ProjectX ;
    ex:accessHour 20 .

ex:Event3 a ex:AccessEvent ;
    ex:accessedBy ex:Emp2 ;
    ex:accessedResource ex:Resource_ProjectX ;
    ex:accessHour 21 .

ex:Event4 a ex:AccessEvent ;
    ex:accessedBy ex:Emp2 ;
    ex:accessedResource ex:Resource_ProjectY ;
    ex:accessHour 19 .

ex:Event5 a ex:AccessEvent ;
    ex:accessedBy ex:Emp3 ;
    ex:accessedResource ex:Resource_ProjectX ;
    ex:accessHour 22 .

ex:Event6 a ex:AccessEvent ;
    ex:accessedBy ex:Emp1 ;
    ex:accessedResource ex:Resource_ProjectX ;
    ex:accessHour 10 .
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
