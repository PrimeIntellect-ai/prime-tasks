#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential pkg-config libssl-dev
    pip3 install pytest

    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    chmod -R 777 /opt/rustup /opt/cargo
    export PATH=/opt/cargo/bin:$PATH

    mkdir -p /home/user

    cat << 'EOF' > /home/user/research_data.ttl
@prefix ex: <http://example.org/> .
@prefix dc: <http://purl.org/dc/elements/1.1/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

ex:Author1 a foaf:Person ; foaf:name "Dr. Alpha" .
ex:Author2 a foaf:Person ; foaf:name "Dr. Bravo" .
ex:Author3 a foaf:Person ; foaf:name "Dr. Charlie" .
ex:Author4 a foaf:Person ; foaf:name "Dr. Delta" .

ex:PaperA a ex:Article ;
    dc:title "Advances in Graph Databases" ;
    dc:date 2019 ;
    ex:hasAuthor ex:Author1, ex:Author2 .

ex:PaperB a ex:Article ;
    dc:title "Machine Learning for RDF" ;
    dc:date 2020 ;
    ex:hasAuthor ex:Author3 .

ex:PaperC a ex:Article ;
    dc:title "Legacy Systems" ;
    dc:date 2015 ;
    ex:hasAuthor ex:Author4 .

ex:PaperD a ex:Article ;
    dc:title "SPARQL Optimization Techniques" ;
    dc:date 2019 ;
    ex:hasAuthor ex:Author1, ex:Author4 .

ex:PaperE a ex:Article ;
    dc:title "Quantum Computing Basics" ;
    dc:date 2021 ;
    ex:hasAuthor ex:Author2 .

# Citations
ex:PaperB ex:cites ex:PaperA .
ex:PaperC ex:cites ex:PaperA .
ex:PaperD ex:cites ex:PaperA .
ex:PaperE ex:cites ex:PaperA .

ex:PaperA ex:cites ex:PaperB .
ex:PaperD ex:cites ex:PaperB .
ex:PaperE ex:cites ex:PaperB .

ex:PaperA ex:cites ex:PaperD .
ex:PaperE ex:cites ex:PaperD .

ex:PaperA ex:cites ex:PaperC .
ex:PaperB ex:cites ex:PaperC .
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
