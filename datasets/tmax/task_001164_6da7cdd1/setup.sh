#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/knowledge_graph.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT, name TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER, relation TEXT);

INSERT INTO nodes (id, type, name) VALUES
(1, 'Author', 'Alice Smith'),
(2, 'Author', 'Bob Jones'),
(3, 'Author', 'Charlie Brown'),
(4, 'Paper', 'Graph Query Optimization'),
(5, 'Paper', 'C Programming Tips'),
(6, 'Paper', 'Deep Learning Graphs'),
(7, 'Dataset', 'GraphDB-1M'),
(8, 'Dataset', 'Code-Corpus'),
(9, 'Dataset', 'ImageNet-Mini'),
(10, 'Topic', 'Machine Learning'),
(11, 'Topic', 'Compilers');

INSERT INTO edges (source, target, relation) VALUES
(1, 4, 'authored'),
(4, 7, 'uses'),
(7, 10, 'tagged'),

(2, 5, 'authored'),
(5, 8, 'uses'),
(8, 11, 'tagged'),

(2, 4, 'authored'),

(3, 6, 'authored'),
(6, 9, 'uses'),
(9, 10, 'tagged');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
