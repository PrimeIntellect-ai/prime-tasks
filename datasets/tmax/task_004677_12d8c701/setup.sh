#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.sql
CREATE TABLE authors (auth_id TEXT, name TEXT);
CREATE TABLE documents (doc_id TEXT, metadata TEXT);
CREATE TABLE citations (source_doc TEXT, target_doc TEXT);

INSERT INTO authors VALUES ('a1', 'Alice'), ('a2', 'Bob'), ('a3', 'Charlie'), ('a4', 'Diana'), ('a5', 'Eve');

INSERT INTO documents VALUES
('d1', '{"year": 2020, "authors": ["a1", "a2"]}'),
('d2', '{"year": 2021, "authors": ["a3"]}'),
('d3', '{"year": 2022, "authors": ["a4"]}'),
('d4', '{"year": 2020, "authors": ["a1"]}'),
('d5', '{"year": 2023, "authors": ["a1"]}'),
('d6', '{"year": 2018, "authors": ["a3"]}'),
('d7', '{"year": 2019, "authors": ["a5"]}'),
('d8', '{"year": 2021, "authors": ["a5"]}');

INSERT INTO citations VALUES
('d2', 'd1'),
('d3', 'd2'), 
('d3', 'd1'),
('d4', 'd2'),
('d5', 'd2'), 
('d5', 'd6'),
('d5', 'd7'),
('d8', 'd1'),
('d8', 'd4');
EOF

sqlite3 /home/user/dataset.db < /tmp/setup.sql
rm /tmp/setup.sql

chmod -R 777 /home/user
