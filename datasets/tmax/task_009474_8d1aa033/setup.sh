#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gnupg
    pip3 install pytest pymongo

    # Install MongoDB (not in default 22.04 repos)
    curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | \
        gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | \
        tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update
    apt-get install -y mongodb-org

    # Create raw data directory and files
    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/papers.json
[
  {"paper_id": "P001", "title": "Foundation of Graph DBs", "impact_factor": 5.0, "cites": [], "author_id": "A1"},
  {"paper_id": "P002", "title": "Scaling Graph DBs", "impact_factor": 3.0, "cites": ["P001"], "author_id": "A2"},
  {"paper_id": "P003", "title": "Distributed Graphs", "impact_factor": 4.5, "cites": ["P002"], "author_id": "A3"},
  {"paper_id": "P004", "title": "Graph DBs in Cloud", "impact_factor": 2.5, "cites": ["P003"], "author_id": "A4"},
  {"paper_id": "P005", "title": "Too Deep Graph", "impact_factor": 1.0, "cites": ["P004"], "author_id": "A5"},
  {"paper_id": "P006", "title": "Unrelated DB", "impact_factor": 6.0, "cites": [], "author_id": "A1"}
]
EOF

    cat << 'EOF' > /home/user/raw_data/authors.json
[
  {"author_id": "A1", "name": "Dr. Alice", "institution": "MIT"},
  {"author_id": "A2", "name": "Dr. Bob", "institution": "Stanford"},
  {"author_id": "A3", "name": "Dr. Charlie", "institution": "CMU"},
  {"author_id": "A4", "name": "Dr. Dana", "institution": "Berkeley"},
  {"author_id": "A5", "name": "Dr. Eve", "institution": "UCL"}
]
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
