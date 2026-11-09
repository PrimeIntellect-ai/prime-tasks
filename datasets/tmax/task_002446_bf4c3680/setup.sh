#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest rdflib

    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/datasets/topics.ttl
@prefix ex: <http://example.org/topics/> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

ex:ArtificialIntelligence a rdfs:Class .
ex:MachineLearning rdfs:subClassOf ex:ArtificialIntelligence .
ex:DeepLearning rdfs:subClassOf ex:MachineLearning .
ex:NaturalLanguageProcessing rdfs:subClassOf ex:ArtificialIntelligence .
ex:LargeLanguageModels rdfs:subClassOf ex:NaturalLanguageProcessing .

ex:Biology a rdfs:Class .
ex:Genetics rdfs:subClassOf ex:Biology .
ex:Bioinformatics rdfs:subClassOf ex:Biology .
EOF

    sqlite3 /home/user/datasets/authors.db << 'EOF'
CREATE TABLE authors (author_id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE papers (paper_id INTEGER PRIMARY KEY, title TEXT, author_id INTEGER, topic_uri TEXT);

INSERT INTO authors (author_id, name) VALUES (1, 'Ada Lovelace');
INSERT INTO authors (author_id, name) VALUES (2, 'Alan Turing');
INSERT INTO authors (author_id, name) VALUES (3, 'Rosalind Franklin');
INSERT INTO authors (author_id, name) VALUES (4, 'Grace Hopper');

INSERT INTO papers (paper_id, title, author_id, topic_uri) VALUES (101, 'Computing Machinery and Intelligence', 2, 'http://example.org/topics/ArtificialIntelligence');
INSERT INTO papers (paper_id, title, author_id, topic_uri) VALUES (102, 'Notes on the Analytical Engine', 1, 'http://example.org/topics/MachineLearning');
INSERT INTO papers (paper_id, title, author_id, topic_uri) VALUES (103, 'Deep Neural Nets', 2, 'http://example.org/topics/DeepLearning');
INSERT INTO papers (paper_id, title, author_id, topic_uri) VALUES (104, 'Understanding DNA', 3, 'http://example.org/topics/Genetics');
INSERT INTO papers (paper_id, title, author_id, topic_uri) VALUES (105, 'Compilers and Code', 4, 'http://example.org/topics/SoftwareEngineering');
INSERT INTO papers (paper_id, title, author_id, topic_uri) VALUES (106, 'The Imitation Game', 2, 'http://example.org/topics/NaturalLanguageProcessing');
INSERT INTO papers (paper_id, title, author_id, topic_uri) VALUES (107, 'Advanced LLMs', 1, 'http://example.org/topics/LargeLanguageModels');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
