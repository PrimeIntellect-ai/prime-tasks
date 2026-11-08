#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset

    cat << 'EOF' > /home/user/dataset/authors.csv
paper_id,author_name
P1,Alice Smith
P1,Bob Jones
P2,Charlie Brown
P3,Alice Smith
P4,Dave Miller
P4,Eve Taylor
P5,Frank White
P6,Grace Lee
EOF

    cat << 'EOF' > /home/user/dataset/papers.jsonl
{"paper_id": "P1", "title": "Deep Neural Nets", "abstract": "A study on neural networks and their applications."}
{"paper_id": "P2", "title": "Graph Theory", "abstract": "Graphs are fun and useful for relational data."}
{"paper_id": "P3", "title": "Neural Graph Search", "abstract": "Combining neural and graph techniques."}
{"paper_id": "P4", "title": "Advanced Neural stuff", "abstract": "More neural things to consider."}
{"paper_id": "P5", "title": "AI stuff", "abstract": "Just artificial intelligence without neural components."}
{"paper_id": "P6", "title": "Neurology basics", "abstract": "Neurology is not the same as neural."}
EOF

    cat << 'EOF' > /home/user/dataset/citations.txt
P2 P1
P3 P1
P4 P1
P5 P1
P6 P1
P1 P3
P2 P3
P5 P3
P1 P4
P2 P4
P3 P5
P4 P2
P6 P4
EOF

    chmod -R 777 /home/user
