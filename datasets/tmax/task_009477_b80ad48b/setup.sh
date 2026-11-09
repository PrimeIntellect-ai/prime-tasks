#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest rdflib

mkdir -p /home/user
cat << 'EOF' > /home/user/org_graph.ttl
@prefix ex: <http://example.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix org: <http://www.w3.org/ns/org#> .

ex:DeptIT a org:OrganizationalUnit ;
    foaf:name "IT" .

ex:DeptSecurity a org:OrganizationalUnit ;
    foaf:name "Security" .

ex:DeptSales a org:OrganizationalUnit ;
    foaf:name "Sales" .

ex:DeptDirectSales a org:OrganizationalUnit ;
    foaf:name "Direct Sales" ;
    org:subOrganizationOf ex:DeptSales .

ex:DeptOps a org:OrganizationalUnit ;
    foaf:name "Operations" .

ex:DeptNetOps a org:OrganizationalUnit ;
    foaf:name "Network Operations" ;
    org:subOrganizationOf ex:DeptIT .

ex:Emp1 a foaf:Person ;
    foaf:name "Alice Smith" ;
    org:memberOf ex:DeptIT .

ex:Emp2 a foaf:Person ;
    foaf:name "Bob Jones" ;
    org:memberOf ex:DeptSales .

ex:Emp3 a foaf:Person ;
    foaf:name "Charlie Brown" ;
    org:memberOf ex:DeptDirectSales .

ex:Emp4 a foaf:Person ;
    foaf:name "Diana Prince" ;
    org:memberOf ex:DeptSecurity .

ex:Emp5 a foaf:Person ;
    foaf:name "Eve Davis" ;
    org:memberOf ex:DeptNetOps .

ex:Emp6 a foaf:Person ;
    foaf:name "Frank Miller" ;
    org:memberOf ex:DeptOps .

ex:Access1 ex:accessedBy ex:Emp1 ; ex:system "System_Omega" .
ex:Access2 ex:accessedBy ex:Emp2 ; ex:system "System_Omega" .
ex:Access3 ex:accessedBy ex:Emp3 ; ex:system "System_Omega" .
ex:Access4 ex:accessedBy ex:Emp4 ; ex:system "System_Omega" .
ex:Access5 ex:accessedBy ex:Emp5 ; ex:system "System_Omega" .
ex:Access6 ex:accessedBy ex:Emp6 ; ex:system "System_Omega" .
ex:Access7 ex:accessedBy ex:Emp6 ; ex:system "System_Alpha" .
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
