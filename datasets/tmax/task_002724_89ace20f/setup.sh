#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
from rdflib import Graph, Literal, Namespace
from rdflib.namespace import RDF, XSD

EX = Namespace("http://example.org/")

g = Graph()
g.bind("ex", EX)

# Add papers and years
g.add((EX.paper1, RDF.type, EX.Paper))
g.add((EX.paper1, EX.year, Literal(2010, datatype=XSD.integer)))

g.add((EX.paper2, RDF.type, EX.Paper)) # Filtered out (2005)
g.add((EX.paper2, EX.year, Literal(2005, datatype=XSD.integer)))

g.add((EX.paper3, RDF.type, EX.Paper))
g.add((EX.paper3, EX.year, Literal(2012, datatype=XSD.integer)))

g.add((EX.paper4, RDF.type, EX.Paper))
g.add((EX.paper4, EX.year, Literal(2015, datatype=XSD.integer)))

g.add((EX.paper5, RDF.type, EX.Paper))
g.add((EX.paper5, EX.year, Literal(2011, datatype=XSD.integer)))

g.add((EX.paper6, RDF.type, EX.Paper))
g.add((EX.paper6, EX.year, Literal(2020, datatype=XSD.integer)))

# Citations (paper A cites paper B means B has an incoming edge from A)
cites = EX.cites

# paper1 cited by 2,3,4,5,6 (in-degree 5)
g.add((EX.paper2, cites, EX.paper1))
g.add((EX.paper3, cites, EX.paper1))
g.add((EX.paper4, cites, EX.paper1))
g.add((EX.paper5, cites, EX.paper1))
g.add((EX.paper6, cites, EX.paper1))

# paper2 cited by 3,4,5,6,7 (in-degree 5, but filtered out)
g.add((EX.paper3, cites, EX.paper2))
g.add((EX.paper4, cites, EX.paper2))
g.add((EX.paper5, cites, EX.paper2))
g.add((EX.paper6, cites, EX.paper2))

# paper3 cited by 4,5 (in-degree 2)
g.add((EX.paper4, cites, EX.paper3))
g.add((EX.paper5, cites, EX.paper3))

# paper4 cited by 5,6 (in-degree 2)
g.add((EX.paper5, cites, EX.paper4))
g.add((EX.paper6, cites, EX.paper4))

# paper5 cited by 6 (in-degree 1)
g.add((EX.paper6, cites, EX.paper5))

g.serialize(destination="/home/user/graph.ttl", format="turtle")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
