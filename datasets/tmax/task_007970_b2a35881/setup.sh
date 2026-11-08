#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq
pip3 install pytest rdflib

mkdir -p /home/user

cat << 'EOF' > /home/user/data.ttl
@prefix ex: <http://example.org/> .

ex:Movie1 ex:type ex:Movie ;
    ex:title "Tremors" ;
    ex:hasActor ex:KevinBacon, ex:FredWard, ex:FinnCarter .

ex:Movie2 ex:type ex:Movie ;
    ex:title "Footloose" ;
    ex:hasActor ex:KevinBacon, ex:LoriSinger, ex:JohnLithgow .

ex:Movie3 ex:type ex:Movie ;
    ex:title "Apollo 13" ;
    ex:hasActor ex:KevinBacon, ex:TomHanks, ex:BillPaxton .

ex:Movie4 ex:type ex:Movie ;
    ex:title "Cast Away" ;
    ex:hasActor ex:TomHanks .

ex:KevinBacon ex:name "Kevin Bacon" .
ex:FredWard ex:name "Fred Ward" .
ex:FinnCarter ex:name "Finn Carter" .
ex:LoriSinger ex:name "Lori Singer" .
ex:JohnLithgow ex:name "John Lithgow" .
ex:TomHanks ex:name "Tom Hanks" .
ex:BillPaxton ex:name "Bill Paxton" .
EOF

cat << 'EOF' > /home/user/slow_query.rq
PREFIX ex: <http://example.org/>
SELECT ?coStarName
WHERE {
  ?m1 ex:type ex:Movie .
  ?m2 ex:type ex:Movie .
  ?m1 ex:hasActor ?a1 .
  ?m2 ex:hasActor ?a2 .
  FILTER(?a1 = ex:KevinBacon && ?m1 = ?m2 && ?a1 != ?a2)
  ?a2 ex:name ?coStarName .
}
EOF

cat << 'EOF' > /home/user/query_runner.py
import sys
import json
try:
    import rdflib
except ImportError:
    print("Please install rdflib: pip install rdflib")
    sys.exit(1)

if len(sys.argv) != 3:
    print("Usage: python3 query_runner.py <data.ttl> <query.rq>")
    sys.exit(1)

g = rdflib.Graph()
g.parse(sys.argv[1], format="turtle")

with open(sys.argv[2], "r") as f:
    query = f.read()

res = g.query(query)
out = {"results": {"bindings": []}}
for row in res:
    binding = {}
    for var in res.vars:
        val = row[var]
        if val is not None:
            binding[str(var)] = {"value": str(val)}
    out["results"]["bindings"].append(binding)

print(json.dumps(out))
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
