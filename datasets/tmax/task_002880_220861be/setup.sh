#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.ttl
@prefix ex: <http://example.org/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

ex:Emp1 ex:name "Alice" ; ex:salary 90000 ; ex:worksIn ex:Dept1 .
ex:Emp2 ex:name "Bob" ; ex:salary 60000 ; ex:worksIn ex:Dept1 .
ex:Emp3 ex:name "Charlie" ; ex:salary 40000 ; ex:worksIn ex:Dept1 . 
ex:Emp4 ex:name "Diana" ; ex:salary 120000 ; ex:worksIn ex:Dept2 .
ex:Emp5 ex:name "Eve" ; ex:salary 80000 ; ex:worksIn ex:Dept2 .
ex:Emp6 ex:name "Frank" ; ex:salary 110000 ; ex:worksIn ex:Dept3 .

ex:Dept1 ex:deptName "Engineering" .
ex:Dept2 ex:deptName "Sales" .
ex:Dept3 ex:deptName "Marketing" .
EOF

    cat << 'EOF' > /home/user/report.py
import rdflib
import csv

g = rdflib.Graph()
g.parse("/home/user/data.ttl", format="turtle")

MIN_SALARY = 50000

# BUGGY QUERY: Missing relationship between ?emp and ?dept, causing a cross join.
# Also missing aggregation, grouping, sorting, pagination, and parameterization.
query = """
PREFIX ex: <http://example.org/>
SELECT ?deptName ?salary
WHERE {
    ?emp ex:salary ?salary .
    ?dept ex:deptName ?deptName .
}
"""

results = g.query(query)

with open('/home/user/summary.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    for row in results:
        writer.writerow([row.deptName, row.salary])
EOF

    chmod -R 777 /home/user
