#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib pandas

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/publications.ttl
@prefix ex: <http://example.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

ex:Pub1 a ex:Publication ;
    ex:hasTopic ex:topic/MachineLearning ;
    ex:hasAuthor ex:AuthorAlice, ex:AuthorBob .

ex:Pub2 a ex:Publication ;
    ex:hasTopic ex:topic/MachineLearning ;
    ex:hasAuthor ex:AuthorAlice, ex:AuthorCharlie .

ex:Pub3 a ex:Publication ;
    ex:hasTopic ex:topic/Databases ;
    ex:hasAuthor ex:AuthorBob .

ex:Pub4 a ex:Publication ;
    ex:hasTopic ex:topic/MachineLearning ;
    ex:hasAuthor ex:AuthorCharlie .

ex:AuthorAlice foaf:name "Alice Smith" .
ex:AuthorBob foaf:name "Bob Jones" .
ex:AuthorCharlie foaf:name "Charlie Brown" .
EOF

    cat << 'EOF' > /home/user/data/experiments.jsonl
{"pub_id": "Pub1", "experiment_id": "e1", "metrics": {"accuracy": 0.950, "f1_score": 0.920}}
{"pub_id": "Pub1", "experiment_id": "e2", "metrics": {"accuracy": 0.960, "f1_score": 0.930}}
{"pub_id": "Pub2", "experiment_id": "e3", "metrics": {"accuracy": 0.880, "f1_score": 0.850}}
{"pub_id": "Pub2", "experiment_id": "e4", "metrics": {"accuracy": 0.890, "f1_score": 0.860}}
{"pub_id": "Pub3", "experiment_id": "e5", "metrics": {"accuracy": 0.990, "f1_score": 0.990}}
{"pub_id": "Pub4", "experiment_id": "e6", "metrics": {"accuracy": 0.910, "f1_score": 0.900}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
