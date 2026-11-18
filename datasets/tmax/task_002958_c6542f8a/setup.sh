#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    sqlite3 dataset.db <<EOF
CREATE TABLE researchers (
    id INTEGER PRIMARY KEY,
    full_name TEXT NOT NULL,
    institution TEXT
);

CREATE TABLE publications (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    year INTEGER
);

CREATE TABLE authorship (
    researcher_id INTEGER,
    publication_id INTEGER,
    author_order INTEGER,
    FOREIGN KEY(researcher_id) REFERENCES researchers(id),
    FOREIGN KEY(publication_id) REFERENCES publications(id)
);

CREATE TABLE references_tbl (
    source_pub_id INTEGER,
    target_pub_id INTEGER,
    FOREIGN KEY(source_pub_id) REFERENCES publications(id),
    FOREIGN KEY(target_pub_id) REFERENCES publications(id)
);

INSERT INTO researchers (id, full_name, institution) VALUES
(1, 'Dr. Alan Turing', 'Bletchley'),
(2, 'Grace Hopper', 'Navy'),
(3, 'Ada Lovelace', 'London'),
(4, 'John von Neumann', 'IAS'),
(5, 'Claude Shannon', 'MIT'),
(6, 'Donald Knuth', 'Stanford');

INSERT INTO publications (id, title, year) VALUES
(101, 'Computing Machinery and Intelligence', 1950),
(102, 'A Manual of Operation for the Automatic Sequence Controlled Calculator', 1946),
(103, 'Notes on the Analytical Engine', 1843),
(104, 'First Draft of a Report on the EDVAC', 1945),
(105, 'A Mathematical Theory of Communication', 1948),
(106, 'The Art of Computer Programming', 1968),
(107, 'Secondary Paper A', 1990),
(108, 'Secondary Paper B', 1991);

INSERT INTO authorship (researcher_id, publication_id, author_order) VALUES
(1, 101, 1),
(2, 102, 1),
(3, 103, 1),
(4, 104, 1),
(5, 105, 1),
(6, 106, 1),
(1, 107, 1),
(2, 107, 2),
(5, 108, 1);

-- target_pub_id is the one being cited
INSERT INTO references_tbl (source_pub_id, target_pub_id) VALUES
(102, 101),
(104, 101),
(105, 101),
(107, 101),
(108, 101),

(101, 105),
(106, 105),
(107, 105),
(108, 105),

(105, 104),
(106, 104),
(107, 104),

(104, 106),
(108, 106),

(108, 107);
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
