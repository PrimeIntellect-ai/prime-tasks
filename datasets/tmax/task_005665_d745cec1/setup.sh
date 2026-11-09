#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    # Create SQLite database
    sqlite3 papers.db <<EOF
CREATE TABLE papers(id INTEGER PRIMARY KEY, title TEXT, author TEXT);
INSERT INTO papers VALUES(101, 'Computing Machinery and Intelligence', 'Dr. Alan Turing');
INSERT INTO papers VALUES(102, 'On Computable Numbers', 'Dr. Alan Turing');
INSERT INTO papers VALUES(201, 'Modern AI', 'Dr. John Doe');
INSERT INTO papers VALUES(202, 'Turing Machines Reevaluated', 'Dr. Jane Smith');
INSERT INTO papers VALUES(203, 'History of Computing', 'Dr. Alice Jones');
INSERT INTO papers VALUES(204, 'Quantum Automata', 'Dr. John Doe');
EOF

    # Create citation graph
    cat <<EOF > citations.txt
101 201
101 202
102 202
102 203
201 204
EOF

    # Create abstracts document store
    cat <<EOF > abstracts.txt
101|I propose to consider the question, Can machines think?
102|We briefly describe the universal computing machine.
201|An overview of modern artificial intelligence and its roots.
202|This paper reevaluates the concept of the Turing machine in the 21st century.
203|A comprehensive history of computing from the 1930s to today.
204|Exploring the intersection of quantum mechanics and automata theory.
EOF

    chmod -R 777 /home/user
