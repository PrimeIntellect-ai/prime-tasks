#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    mkdir -p /home/user
    cat << 'EOF' > /home/user/company_data.ttl
@prefix ex: <http://example.org/> .

ex:Alice a ex:Employee ;
    ex:worksIn ex:DeptA ;
    ex:assignedTo ex:Proj2 .

ex:Bob a ex:Employee ;
    ex:worksIn ex:DeptB ;
    ex:assignedTo ex:Proj1 .

ex:Charlie a ex:Employee ;
    ex:worksIn ex:DeptC ;
    ex:assignedTo ex:Proj4 .

ex:Diana a ex:Employee ;
    ex:worksIn ex:DeptD ;
    ex:assignedTo ex:Proj3 .

ex:Eve a ex:Employee ;
    ex:worksIn ex:DeptA ;
    ex:assignedTo ex:Proj1 .

ex:DeptA a ex:Department ;
    ex:managesProject ex:Proj1 .

ex:DeptB a ex:Department ;
    ex:managesProject ex:Proj2 .

ex:DeptC a ex:Department ;
    ex:managesProject ex:Proj3 .

ex:DeptD a ex:Department ;
    ex:managesProject ex:Proj4 .
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
